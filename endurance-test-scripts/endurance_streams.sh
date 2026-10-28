#!/bin/bash

# Redis Benchmark Parameters
REDIS_PWD="${REDIS_PWD:?Set REDIS_PWD}"
PROXY_HOST="${PROXY_HOST:?Set PROXY_HOST}"
PROXY_PORT="${PROXY_PORT:-6379}"
REQUESTS=2000
CONNECTIONS=200
output_file="benchmark_output.json"

# Redis Commands with Subcommands and Actual Values
commands=(
  "lpush mylist value1"
  "lset mylist 0 new_value"
  "lpos mylist value1"
  "bitpos mykey 1"
  "xadd mystream * field1 value1"
  "xrange mystream - +"
  "xrevrange mystream + -"
  "xlen mystream"
  "xdel mystream 1526569495633-0"
  "xtrim mystream MAXLEN 1000"
  "XGROUP SETID mystream mygroup 0"
  "rename {mykey} {newkey}"
  "eval \"return redis.call('set', KEYS[1], ARGV[1])\" 1 mykey myvalue"
  # SCRIPT LOAD "return redis.call('set', KEYS[1], ARGV[1])"
  "evalsha f77c0e991bb9aa18d4a3e247b1cfa742aa5c0d00 1 mykey myvalue"
)

# Loop through each command and run the benchmark with a separate log file for each command
for cmd in "${commands[@]}"; do
  # Replace spaces in $cmd with underscores for the filename
  log_file="benchmark_output_${cmd// /_}.log"

  echo "Running benchmark for command: $cmd"

  ./redis-benchmark-go -a "$REDIS_PWD" -h "$PROXY_HOST" -p "$PROXY_PORT" -rps "$REQUESTS" -c "$CONNECTIONS" -l -cmd "$cmd" --json-out-file "${cmd// /_}_output.json" > "$log_file" 2>&1 &
done