#!/bin/bash

# Sample command to run
# ./endurance_automation.sh <redis_password> <proxy_host> <proxy_port> 500 200 result_cx.txt commands.txt
# Check if correct number of arguments is provided
if [ "$#" -ne 7 ]; then
    echo "Usage: $0 <redis_password> <proxy_host> <proxy_port> <requests> <connections> <res_file> <commands_file>"
    exit 1
fi

# Assign arguments to variables
REDIS_PWD="$1"
PROXY_HOST="$2"
PROXY_PORT="$3"
REQUESTS="$4"
CONNECTIONS="$5"
RES_FILE="$6"
COMMANDS_FILE="$7"

# Function to escape special characters in commands
escape_command() {
    echo "$1" | sed 's/"/\\"/g'
}

# Function to run benchmark for a single command
run_benchmark() {
    local cmd="$1"
    local output_file="results_endurance/${RES_FILE}_${cmd// /_}.json"
    local log_file="results_endurance/${RES_FILE}_${cmd// /_}.log"

    benchmark_command="./redis-benchmark-go -a $REDIS_PWD -h $PROXY_HOST -p $PROXY_PORT -rps $REQUESTS -c $CONNECTIONS -l -cmd \"$cmd\" --json-out-file $output_file"

    echo "Executing benchmark command for: $cmd"
    eval "$benchmark_command" > "$log_file" 2>&1 &
    sleep 2
    echo "Benchmark started for: $cmd (PID: $!)"
}

# Read commands from file and run benchmarks
while IFS= read -r cmd || [ -n "$cmd" ]; do
    escaped_cmd=$(escape_command "$cmd")
    run_benchmark "$escaped_cmd"
done < "$COMMANDS_FILE"

# Wait for all background processes to finish
wait

# Process results
echo "All benchmarks completed. Processing results..."

while IFS= read -r cmd || [ -n "$cmd" ]; do
    escaped_cmd=$(escape_command "$cmd")
    log_file="${RES_FILE}_${escaped_cmd// /_}.log"

    if grep -q "error" "$log_file"; then
        error_msg=$(grep "error" "$log_file" | head -n 1)
        echo "$(date) : ERROR : Load test execution failed for command: $cmd - $REQUESTS requests across $CONNECTIONS connections."
        echo "Error message: $error_msg"
    else
        TIME_IN_SECS=$(grep "Total Duration" "$log_file" | tail -1 | awk -F " Seconds" '{print $1}' | awk -F "Total Duration " '{print $2}')
        TOTAL_ERRORS=$(grep "Total Errors" "$log_file" | tail -1 | awk -F "Total Errors " '{print $2}')
        THROUGHPUT=$(grep "Throughput summary" "$log_file" | tail -1 | awk -F ": " '{print $2}')
        echo "$(date) : INFO : Command: $cmd - $REQUESTS requests across $CONNECTIONS connections took ${TIME_IN_SECS}s and throughput value is $THROUGHPUT with $TOTAL_ERRORS errors."
    fi
done < "$COMMANDS_FILE"