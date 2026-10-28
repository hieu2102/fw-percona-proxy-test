#!/bin/bash

LOG_FILE="envoy_asan_build.log"
ENVOY_CONFIG="envoy.yaml"
ENVOY_BINARY="./bazel-bin/source/exe/envoy-static"
REDIS_PORT=1999
CHANNEL="test_channel"
PATTERN="test_*"
ENVOY_PID=

wait_for_envoy() {
    local timeout=600
    local start_time=$(date +%s)
    while true; do
        if pgrep -f ".*envoy-static" > /dev/null; then
            echo "Envoy started"
            ENVOY_PID=$(pgrep -f ".*envoy-static")
            return 0
        fi
        if [ $(($(date +%s) - start_time)) -gt $timeout ]; then
            echo "Timed out waiting for Envoy to start"
            return 1
        fi
        sleep 1
    done
}

check_redis_ping() {
    local timeout=600
    local start_time=$(date +%s)
    while true; do
        if redis-cli -c -h 127.0.0.1 -p $REDIS_PORT PING 2>/dev/null | grep -q "PONG"; then
            echo "Redis cluster is responsive"
            return 0
        fi
        if [ $(($(date +%s) - start_time)) -gt $timeout ]; then
            echo "Timed out waiting for Redis cluster to respond"
            return 1
        fi
        sleep 1
    done
}

kill_envoy() {
    local timeout=900
    local start_time=$(date +%s)
    if [ -n "$ENVOY_PID" ]; then
        kill -15 $ENVOY_PID
        while kill -0 $ENVOY_PID 2>/dev/null; do
            if [ $(($(date +%s) - start_time)) -gt $timeout ]; then
                echo "Timed out waiting for Envoy to terminate"
                return 1
            fi
            sleep 1
        done
    fi
    echo "Envoy terminated"
}

execute_redis_command() {
    local max_retries=3
    local retry_count=0
    local result

    while [ $retry_count -lt $max_retries ]; do
        result=$(redis-cli -c -h 127.0.0.1 -p $REDIS_PORT "$@" 2>&1)
        if [ $? -eq 0 ]; then
            echo "$result"
            return 0
        fi
        echo "Command failed, retrying... (Attempt $((retry_count+1)))"
        retry_count=$((retry_count+1))
        sleep 1
    done

    echo "Error: Redis command failed after $max_retries attempts: $result" >&2
    return 1
}

publish_messages() {
    echo "Publishing messages to channel '$CHANNEL' on port $REDIS_PORT"
    execute_redis_command PUBLISH "$CHANNEL" "Message 1"
    execute_redis_command PUBLISH "$CHANNEL" "Message 2"
    execute_redis_command PUBLISH "$CHANNEL" "Message 3"
    execute_redis_command PUBLISH "$CHANNEL" "Message 4"
    execute_redis_command PUBLISH "$CHANNEL" "Message 5"
}

subscribe_pattern() {
    echo "Subscribing to pattern '$PATTERN' on port $REDIS_PORT"
    timeout 5s redis-cli -c -h 127.0.0.1 -p $REDIS_PORT PSUBSCRIBE "$PATTERN" &
    PSUB_PID=$!
    sleep 2
}

subscribe_channel() {
    echo "Subscribing to channel '$CHANNEL' on port $REDIS_PORT"
    timeout 5s redis-cli -c -h 127.0.0.1 -p $REDIS_PORT SUBSCRIBE "$CHANNEL" &
    SUB_PID=$!
    sleep 2
}

unsubscribe_pattern() {
    echo "Unsubscribing from pattern '$PATTERN' and channel '$CHANNEL' on port $REDIS_PORT"
    execute_redis_command PUNSUBSCRIBE "$PATTERN"
    execute_redis_command UNSUBSCRIBE "$CHANNEL"
    sleep 2
}

perform_pubsub_commands() {
    echo "Checking the number of subscribers to channel '$CHANNEL' on port $REDIS_PORT"
    execute_redis_command PUBSUB NUMSUB "$CHANNEL"

    echo "Checking the number of pattern subscriptions on port $REDIS_PORT"
    execute_redis_command PUBSUB NUMPAT

    echo "Listing all channels with active subscribers on port $REDIS_PORT"
    execute_redis_command PUBSUB CHANNELS
}

list_subscriptions() {
    echo "Listing current subscriptions on port $REDIS_PORT"
    execute_redis_command PUBSUB CHANNELS
}

run_pubsub_test() {
    echo "Testing Redis PUB/SUB Commands on port $REDIS_PORT"

    subscribe_pattern || return 1
    subscribe_channel || return 1
    sleep 2

    list_subscriptions || return 1
    publish_messages || return 1
    perform_pubsub_commands || return 1
    unsubscribe_pattern || return 1
    list_subscriptions || return 1

    echo "PUB/SUB Test complete"
    return 0
}

run_xread_test() {
    echo "Testing Redis XREAD Commands on port $REDIS_PORT"

    # Create streams with valid IDs
    execute_redis_command XADD mystream * field1 value1
    local stream_id=$(execute_redis_command XADD mystream * field2 value2)

    # Test XREAD
    echo "Testing XREAD"
    execute_redis_command XREAD COUNT 2 STREAMS mystream 0-0

    # Test XREAD BLOCK
    echo "Testing XREAD BLOCK (will timeout after 5 seconds)"
    timeout 5s redis-cli -c -h 127.0.0.1 -p $REDIS_PORT XREAD BLOCK 5000 COUNT 1 STREAMS mystream $stream_id

    echo "XREAD Test complete"
}

run_xreadgroup_test() {
    echo "Testing Redis XREADGROUP Commands on port $REDIS_PORT"

    # Create streams and consumer groups
    execute_redis_command XADD order_stream * order 1
    execute_redis_command XGROUP CREATE order_stream order_processors 0-0 MKSTREAM
    execute_redis_command XADD notification_stream * notification 1
    execute_redis_command XGROUP CREATE notification_stream notification_handlers 0-0 MKSTREAM
    execute_redis_command XADD sensor_data * sensor 1
    execute_redis_command XGROUP CREATE sensor_data sensor_analyzers 0-0 MKSTREAM
    execute_redis_command XADD event_log1 * event 1
    execute_redis_command XADD event_log2 * event 1
    execute_redis_command XGROUP CREATE event_log1 event_handlers 0-0 MKSTREAM
    execute_redis_command XGROUP CREATE event_log2 event_handlers 0-0 MKSTREAM
    execute_redis_command XADD audit_log * audit 1
    execute_redis_command XGROUP CREATE audit_log audit_reviewers 0-0 MKSTREAM

    # Test XREADGROUP commands
    echo "Testing XREADGROUP"
    execute_redis_command XREADGROUP GROUP order_processors worker1 COUNT 10 STREAMS order_stream ">"
    timeout 5s redis-cli -c -h 127.0.0.1 -p $REDIS_PORT XREADGROUP GROUP notification_handlers mobile_app BLOCK 5000 COUNT 10 STREAMS notification_stream ">"
    execute_redis_command XREADGROUP GROUP sensor_analyzers analyzer1 NOACK STREAMS sensor_data ">"
    execute_redis_command XREADGROUP GROUP event_handlers web_server COUNT 10 STREAMS event_log1 event_log2 ">" ">"
    execute_redis_command XREADGROUP GROUP audit_reviewers admin2 COUNT 10 STREAMS audit_log 0-0

    echo "XREADGROUP Test complete"
}

run_other_commands() {
    echo "Testing other Redis commands on port $REDIS_PORT"

    execute_redis_command SET key1 value1
    execute_redis_command GET key1
    execute_redis_command HSET hash1 field1 value1
    execute_redis_command HGET hash1 field1

    echo "Other commands test complete"
}

start_envoy() {
    $ENVOY_BINARY -c $ENVOY_CONFIG --log-level debug > envoy_console_log.log 2>&1 &
    ENVOY_PID=$!
}

check_envoy_and_ping_redis() {
    if ! wait_for_envoy; then
        echo "Error: Envoy failed to start"
        kill $ENVOY_PID
        wait $ENVOY_PID
        return 1
    fi

    if ! check_redis_ping; then
        echo "Error: Redis did not respond in time"
        kill $ENVOY_PID
        wait $ENVOY_PID
        return 1
    fi
}

run_test_group() {
    local group_name="$1"

    echo "Running test group: $group_name"

    case "$group_name" in
        "pubsub")
            run_pubsub_test
            ;;
        "xread")
            run_xread_test
            ;;
        "xreadgroup")
            run_xreadgroup_test
            ;;
        "other")
            run_other_commands
            ;;
        *)
            echo "Unknown test group: $group_name"
            return 1
            ;;
    esac

    if ! check_envoy_and_ping_redis; then
        echo "Error: Envoy or Redis failed after $group_name"
        return 1
    fi
}

# Run test groups
start_envoy
if ! check_envoy_and_ping_redis; then
    echo "Error: Unable to connect to Redis"
    exit 1
fi

if ! run_test_group "pubsub"; then
    echo "Error: Tests for pubsub - Failed"
fi

if ! run_test_group "xread"; then
    echo "Error: Tests for xread - Failed"
fi

if ! run_test_group "xreadgroup"; then
    echo "Error: Tests for xreadgroup - Failed"
fi

if ! run_test_group "other"; then
    echo "Error: Tests for other commands - Failed"
fi

if ! kill_envoy; then
    echo "Error: Failed to terminate Envoy"
    kill -9 $ENVOY_PID
fi

wait $ENVOY_PID
echo "Completed testing for all commands - Success"
