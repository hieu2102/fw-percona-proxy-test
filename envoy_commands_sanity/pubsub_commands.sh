#!/bin/bash

REDIS_HOST="${REDIS_HOST:?Set REDIS_HOST to the proxy host}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:?Set REDIS_PASSWORD}"

TEST_CHANNEL="test_channel_100"
SUBSCRIBER_LOG="./subscriber_output.log"

# Function to execute Redis commands
redis_cmd() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" "$@" 2>/dev/null | grep -v option
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

# Existing validations
kill_clients
validate_pubsub_numsub 0
validate_pubsub_numpat 0
echo "$(date) : INFO : Executing PUBLISH command when no subscribers are present for ${TEST_CHANNEL}."
result=$(redis_cmd PUBLISH ${TEST_CHANNEL} "Hello")
command_result=$(echo $result | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
validate_output "PUBLISH" "$command_result" "0"

echo "$(date) : INFO : Subscribing to ${TEST_CHANNEL}"
redis_cmd SUBSCRIBE ${TEST_CHANNEL} > "$SUBSCRIBER_LOG" &
sleep 5
kill_clients
command_result=$(tail -3 ${SUBSCRIBER_LOG} | tr '\n' ' ' | sed 's/ /\\n/g')
validate_output "SUBSCRIBE" "$command_result" "subscribe\n${TEST_CHANNEL}\n1\n"

validate_pubsub_numsub 0
echo "$(date) : INFO : Executing PUBLISH command when 1 subscribe connection is present for ${TEST_CHANNEL}."
redis_cmd SUBSCRIBE ${TEST_CHANNEL} > "$SUBSCRIBER_LOG" &
sleep 5
validate_pubsub_numsub 1
result=$(redis_cmd PUBLISH ${TEST_CHANNEL} "Hello")
command_result=$(echo $result | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
validate_output "PUBLISH" "$command_result" "1"
kill_clients
command_result=$(tail -3 ${SUBSCRIBER_LOG} | tr '\n' ' ' | sed 's/ /\\n/g')
validate_output "SUBSCRIBE" "$command_result" "message\n${TEST_CHANNEL}\nHello\n"

validate_pubsub_numpat 0
echo "$(date) : INFO : PSubscribing to ${TEST_CHANNEL}*"
redis_cmd PSUBSCRIBE ${TEST_CHANNEL}* > "$SUBSCRIBER_LOG" &
sleep 5
validate_pubsub_numpat 1
kill_clients
command_result=$(tail -3 ${SUBSCRIBER_LOG} | tr '\n' ' ' | sed 's/ /\\n/g')
validate_output "PSUBSCRIBE" "$command_result" "psubscribe\n${TEST_CHANNEL}*\n1\n"

echo "$(date) : INFO : Unsubscribing from channel ${TEST_CHANNEL}"
command_result=$(redis_cmd unsubscribe ${TEST_CHANNEL} | egrep "${TEST_CHANNEL}|unsubscribe|0" | wc -l | sed 's/\r//g' | sed 's/ //g')
validate_output "UNSUBSCRIBE" "$command_result" "0"

echo "$(date) : INFO : PUnsubscribing from ${TEST_CHANNEL}*"
command_result=$(redis_cmd unsubscribe ${TEST_CHANNEL} | egrep "${TEST_CHANNEL}|unsubscribe|0" | wc -l | sed 's/\r//g' | sed 's/ //g')
validate_output "PUNSUBSCRIBE" "$command_result" "0"
kill_clients

echo "$(date) : INFO : Listing the subscribed channels and validating if the ${TEST_CHANNEL} is present."
redis_cmd SUBSCRIBE ${TEST_CHANNEL} > /dev/null &
sleep 5
command_result=$(redis_cmd pubsub channels ${TEST_CHANNEL} | grep -w "${TEST_CHANNEL}" | sed 's/\r//g' | sed 's/ //g')
validate_output "PUBSUB CHANNELS" "$command_result" "${TEST_CHANNEL}"
kill_clients

rm -f ${SUBSCRIBER_LOG}