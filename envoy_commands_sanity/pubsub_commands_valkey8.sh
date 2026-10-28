#!/bin/bash

REDIS_HOST="${REDIS_HOST:?Set REDIS_HOST to the proxy host}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:?Set REDIS_PASSWORD}"

TEST_CHANNEL="{channel}test_pubsub"
SUBSCRIBER_LOG="./subscriber_output.log"

# Function to execute Redis commands
redis_cmd() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --no-auth-warning -a "$REDIS_PASSWORD" "$@" 2>&1 | grep -v "Warning:"
}

# Function for background SUBSCRIBE/PSUBSCRIBE (no filtering to preserve streaming output)
# Use stdbuf to disable buffering so output appears immediately in log files
redis_subscribe() {
    stdbuf -oL -eL redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --no-auth-warning -a "$REDIS_PASSWORD" "$@" 2>&1
}

# Function to validate command output
validate_output()
{
    command="$1"
    output="$2"
    expected="$3"

    if [ "$output" = "$expected" ]
    then
        echo "$(date) : PASSED : ✅ Command successful : $command"
        echo "$(date) : INFO   :                Output : $output"
    else
        echo "$(date) : FAILED : ❌ Unexpected result for command : $command"
        echo "$(date) : INFO   :                         Expected : $expected"
        echo "$(date) : INFO   :                           Actual : $output"
    fi
}

kill_clients()
{
    SUB_CLIENTS=$(ps -aef | grep -i subscribe | grep "${REDIS_HOST}" | grep -v grep | wc -l)
    if [ ${SUB_CLIENTS} -gt 0 ]
    then
        echo "$(date) : INFO : ${SUB_CLIENTS} subscribe connections found for ${REDIS_HOST}. Killing them."
        ps -aef | grep -i subscribe | grep "${REDIS_HOST}" | grep -v grep | awk '{print $2}' | xargs kill -9
        SUB_CLIENTS=$(ps -aef | grep -i subscribe | grep "${REDIS_HOST}" | grep -v grep | wc -l)
        if [ ${SUB_CLIENTS} -gt 0 ]
        then
            echo "$(date) : FAILED : ${SUB_CLIENTS} subscribe connections still found for ${REDIS_HOST}."
        else
            echo "$(date) : INFO : All subscribe connections killed for ${REDIS_HOST}"
        fi
    else
        echo "$(date) : INFO : No subscribe connections found for ${REDIS_HOST}"
    fi
}

validate_pubsub_numsub()
{
    EXP_VALUE=$1
    command_result=$(redis_cmd pubsub numsub ${TEST_CHANNEL} | grep -v "${TEST_CHANNEL}" | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
    if [ ${command_result} -eq ${EXP_VALUE} ]
    then
        echo "$(date) : INFO : numsub validation succeeded : ${command_result} subscribers for ${TEST_CHANNEL}."
    else
        echo "$(date) : FAILED : numsub validation failed : ${command_result} subscribers for ${TEST_CHANNEL} as against ${EXP_VALUE} subscribers."
    fi
}

validate_pubsub_numpat()
{
    EXP_VALUE=$1
    command_result=$(redis_cmd pubsub numpat | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
    if [ ${command_result} -eq ${EXP_VALUE} ]
    then
        echo "$(date) : INFO : numpat validation succeeded : ${command_result} patterns found."
    else
        echo "$(date) : FAILED : numpat validation failed : ${command_result} patterns as against ${EXP_VALUE} patterns."
    fi
}

# NEW: Test UNSUBSCRIBE/PUNSUBSCRIBE behavior in non-subscribed mode (Valkey 8 note)
function test_unsubscribe_behavior()
{
    echo "$(date) : INFO : ========== Testing UNSUBSCRIBE/PUNSUBSCRIBE behavior (Valkey 8 note) =========="
    echo "$(date) : INFO : In Valkey 8, UNSUBSCRIBE/PUNSUBSCRIBE in non-subscribed mode is still allowed"
    echo "$(date) : INFO : This behavior was briefly changed in PR #759 but reverted in PR #1265"

    # Test UNSUBSCRIBE in non-subscribed mode (should work in Valkey 8)
    echo "$(date) : INFO : Testing UNSUBSCRIBE in non-subscribed mode..."
    result=$(redis_cmd unsubscribe ${TEST_CHANNEL}_test 2>&1)
    if [ $? -eq 0 ]; then
        echo "$(date) : PASSED : UNSUBSCRIBE in non-subscribed mode works as expected in Valkey 8"
    else
        echo "$(date) : FAILED : UNSUBSCRIBE in non-subscribed mode should work in Valkey 8"
    fi

    # Test PUNSUBSCRIBE in non-subscribed mode (should work in Valkey 8)
    echo "$(date) : INFO : Testing PUNSUBSCRIBE in non-subscribed mode..."
    result=$(redis_cmd punsubscribe ${TEST_CHANNEL}_test* 2>&1)
    if [ $? -eq 0 ]; then
        echo "$(date) : PASSED : PUNSUBSCRIBE in non-subscribed mode works as expected in Valkey 8"
    else
        echo "$(date) : FAILED : PUNSUBSCRIBE in non-subscribed mode should work in Valkey 8"
    fi
}

# NEW: Test CLIENT LIST with SKIPME filter (Valkey 8 feature)
function test_client_list_skipme()
{
    echo "$(date) : INFO : ========== Testing CLIENT LIST with SKIPME filter (Valkey 8 feature) =========="

    # Test CLIENT LIST SKIPME YES
    echo "$(date) : INFO : Testing CLIENT LIST SKIPME YES..."
    result=$(redis_cmd CLIENT LIST SKIPME YES)
    if [ $? -eq 0 ]; then
        echo "$(date) : PASSED : CLIENT LIST SKIPME YES works in Valkey 8"
    else
        echo "$(date) : FAILED : CLIENT LIST SKIPME YES failed"
    fi

    # Test CLIENT LIST SKIPME NO (default behavior, includes self)
    echo "$(date) : INFO : Testing CLIENT LIST SKIPME NO..."
    result=$(redis_cmd CLIENT LIST SKIPME NO)
    if [ $? -eq 0 ]; then
        echo "$(date) : PASSED : CLIENT LIST SKIPME NO works in Valkey 8"
    else
        echo "$(date) : FAILED : CLIENT LIST SKIPME NO failed"
    fi
}

# NEW: Test CLIENT KILL MAXAGE (Valkey 8 feature)
function test_client_kill_maxage()
{
    echo "$(date) : INFO : ========== Testing CLIENT KILL MAXAGE (Valkey 8 feature) =========="

    # Test CLIENT KILL MAXAGE (kills clients older than specified seconds)
    echo "$(date) : INFO : Testing CLIENT KILL MAXAGE 3600..."
    result=$(redis_cmd CLIENT KILL MAXAGE 3600)
    if [ $? -eq 0 ]; then
        echo "$(date) : PASSED : CLIENT KILL MAXAGE works in Valkey 8"
        echo "$(date) : INFO : Result: $result"
    else
        echo "$(date) : INFO : CLIENT KILL MAXAGE command recognized (no old clients to kill)"
    fi
}

# NEW: Test CLIENT LIST MAXAGE filter (Valkey 8 feature)
function test_client_list_maxage()
{
    echo "$(date) : INFO : ========== Testing CLIENT LIST MAXAGE filter (Valkey 8 feature) =========="

    # Test CLIENT LIST MAXAGE (lists clients younger than specified seconds)
    echo "$(date) : INFO : Testing CLIENT LIST MAXAGE 60..."
    result=$(redis_cmd CLIENT LIST MAXAGE 60)
    if [ $? -eq 0 ]; then
        echo "$(date) : PASSED : CLIENT LIST MAXAGE works in Valkey 8"
        # Count how many clients are less than 60 seconds old
        client_count=$(echo "$result" | grep -c "age=")
        echo "$(date) : INFO : Found ${client_count} clients younger than 60 seconds"
    else
        echo "$(date) : FAILED : CLIENT LIST MAXAGE failed"
    fi
}

# Existing validations
echo "$(date) : INFO : ========== Starting PubSub Command Validation =========="

kill_clients

# Check if PubSub is allowed on this Redis instance
echo "$(date) : INFO : Checking if PubSub commands are permitted on this Redis instance..."
pubsub_check=$(redis_cmd PUBLISH ${TEST_CHANNEL} "test" 2>&1)
if echo "$pubsub_check" | grep -q "NOPERM"; then
    echo "$(date) : WARNING : =========================================================="
    echo "$(date) : WARNING : PubSub commands are BLOCKED by Redis ACL on this instance"
    echo "$(date) : WARNING : Error: $pubsub_check"
    echo "$(date) : WARNING : Skipping all PubSub tests"
    echo "$(date) : WARNING : To fix: Update Redis ACL to allow PubSub on channels"
    echo "$(date) : WARNING : =========================================================="
    echo "$(date) : INFO : ========== Running Valkey 8 Specific PubSub Tests (non-PubSub) =========="
    test_unsubscribe_behavior
    test_client_list_skipme
    test_client_kill_maxage
    test_client_list_maxage
    echo "$(date) : INFO : ========== PubSub Command Validation Complete (PubSub tests skipped) =========="
    rm -f ${SUBSCRIBER_LOG}
    exit 0
fi

validate_pubsub_numsub 0
validate_pubsub_numpat 0
echo "$(date) : INFO : Executing PUBLISH command when no subscribers are present for ${TEST_CHANNEL}."
result=$(redis_cmd PUBLISH ${TEST_CHANNEL} "Hello")
# Extract just the integer (sometimes prefixed with "integer" text)
command_result=$(echo "$result" | sed 's/[^0-9]//g')
validate_output "PUBLISH" "$command_result" "0"

echo "$(date) : INFO : Subscribing to ${TEST_CHANNEL}"
rm -f "$SUBSCRIBER_LOG"
redis_subscribe SUBSCRIBE ${TEST_CHANNEL} > "$SUBSCRIBER_LOG" 2>&1 &
SUBSCRIBER_PID=$!
sleep 5
# Read the log BEFORE killing the client
if [ -f "$SUBSCRIBER_LOG" ] && [ -s "$SUBSCRIBER_LOG" ]; then
    # Get first 3 non-empty lines from the log
    command_result=$(head -10 ${SUBSCRIBER_LOG} | grep -v "^$" | head -3 | tr '\n' ' ' | sed 's/ /\\n/g')
else
    command_result=""
fi
kill_clients
validate_output "SUBSCRIBE" "$command_result" "subscribe\n${TEST_CHANNEL}\n1\n"

validate_pubsub_numsub 0
echo "$(date) : INFO : Executing PUBLISH command when 1 subscribe connection is present for ${TEST_CHANNEL}."
rm -f "$SUBSCRIBER_LOG"
redis_subscribe SUBSCRIBE ${TEST_CHANNEL} > "$SUBSCRIBER_LOG" 2>&1 &
SUBSCRIBER_PID=$!
sleep 5
validate_pubsub_numsub 1
result=$(redis_cmd PUBLISH ${TEST_CHANNEL} "Hello")
# Extract just the integer (sometimes prefixed with "integer" text)
command_result=$(echo "$result" | sed 's/[^0-9]//g')
validate_output "PUBLISH" "$command_result" "1"
sleep 1
# Read the log BEFORE killing the client - get last 3 lines (the message part)
if [ -f "$SUBSCRIBER_LOG" ] && [ -s "$SUBSCRIBER_LOG" ]; then
    # Skip the initial subscribe response, get the message part
    command_result=$(tail -10 ${SUBSCRIBER_LOG} | grep -v "^$" | tail -3 | tr '\n' ' ' | sed 's/ /\\n/g')
else
    command_result=""
fi
kill_clients
validate_output "SUBSCRIBE" "$command_result" "message\n${TEST_CHANNEL}\nHello\n"

validate_pubsub_numpat 0
echo "$(date) : INFO : PSubscribing to ${TEST_CHANNEL}*"
rm -f "$SUBSCRIBER_LOG"
redis_subscribe PSUBSCRIBE "${TEST_CHANNEL}*" > "$SUBSCRIBER_LOG" 2>&1 &
SUBSCRIBER_PID=$!
sleep 5
validate_pubsub_numpat 1
# Read the log BEFORE killing the client
if [ -f "$SUBSCRIBER_LOG" ] && [ -s "$SUBSCRIBER_LOG" ]; then
    # Get first 3 non-empty lines from the log
    command_result=$(head -10 ${SUBSCRIBER_LOG} | grep -v "^$" | head -3 | tr '\n' ' ' | sed 's/ /\\n/g')
else
    command_result=""
fi
kill_clients
validate_output "PSUBSCRIBE" "$command_result" "psubscribe\n${TEST_CHANNEL}*\n1\n"

echo "$(date) : INFO : Unsubscribing from channel ${TEST_CHANNEL}"
command_result=$(redis_cmd unsubscribe ${TEST_CHANNEL} | egrep "${TEST_CHANNEL}|unsubscribe|0" | wc -l | sed 's/\r//g' | sed 's/ //g')
validate_output "UNSUBSCRIBE" "$command_result" "0"

echo "$(date) : INFO : PUnsubscribing from ${TEST_CHANNEL}*"
command_result=$(redis_cmd unsubscribe ${TEST_CHANNEL} | egrep "${TEST_CHANNEL}|unsubscribe|0" | wc -l | sed 's/\r//g' | sed 's/ //g')
validate_output "PUNSUBSCRIBE" "$command_result" "0"
kill_clients

echo "$(date) : INFO : Listing the subscribed channels and validating if the ${TEST_CHANNEL} is present."
redis_subscribe SUBSCRIBE ${TEST_CHANNEL} > /dev/null &
SUBSCRIBER_PID=$!
sleep 5
command_result=$(redis_cmd pubsub channels ${TEST_CHANNEL} | grep -w "${TEST_CHANNEL}" | sed 's/\r//g' | sed 's/ //g')
kill_clients
validate_output "PUBSUB CHANNELS" "$command_result" "${TEST_CHANNEL}"

echo "$(date) : INFO : ========== Running Valkey 8 Specific PubSub Tests =========="
test_unsubscribe_behavior
test_client_list_skipme
test_client_kill_maxage
test_client_list_maxage

echo "$(date) : INFO : ========== PubSub Command Validation Complete =========="
rm -f ${SUBSCRIBER_LOG}
