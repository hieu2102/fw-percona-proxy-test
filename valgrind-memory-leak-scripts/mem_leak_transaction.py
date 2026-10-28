import subprocess
import time
import re
import os
import signal

def run_command(command, timeout=5):
    process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        output, error = process.communicate(timeout=timeout)
        return output.decode('utf-8'), error.decode('utf-8')
    except subprocess.TimeoutExpired:
        os.kill(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=60)
        except subprocess.TimeoutExpired:
            os.kill(process.pid, signal.SIGKILL)
            process.wait()

        return "", "Command timed out"

def wait_for_envoy(timeout=600):
    start_time = time.time()
    while True:
        output, _ = run_command("ps -ef | grep valgrind | grep envoy-static")
        if "valgrind" in output and "envoy-static" in output:
            pid = re.search(r'\s*root\s+(\d+)\s+.*valgrind.*envoy-static', output)
            if pid:
                return pid.group(1)
        if time.time() - start_time > timeout:
            raise TimeoutError("Timed out waiting for Envoy to start")
        time.sleep(1)

def check_redis_ping(timeout=600):
    start_time = time.time()
    while True:
        output, _ = run_command("redis-cli -p 1999 PING")
        if "PONG" in output:
            return True
        if time.time() - start_time > timeout:
            raise TimeoutError("Timed out waiting for Redis to respond")
        time.sleep(1)

def kill_envoy(timeout=900):
    start_time = time.time()
    output, _ = run_command("ps -ef | grep valgrind | grep envoy-static")
    pid = re.search(r'\s*root\s+(\d+)\s+.*valgrind.*envoy-static', output)
    if pid:
        envoy_pid = pid.group(1)
        run_command(f"kill -15 {envoy_pid}")
        while True:
            output, _ = run_command(f"ps -p {envoy_pid}")
            if envoy_pid not in output:
                break
            if time.time() - start_time > timeout:
                raise TimeoutError("Timed out waiting for Envoy to terminate")
            time.sleep(1)

def parse_log_file(log_file):
    time.sleep(10)
    output, _ = run_command(f"tail -n 15 {log_file}")
    leak_summary_start = output.find("LEAK SUMMARY:")
    if leak_summary_start != -1:
        lines = output[leak_summary_start:].splitlines()
        if len(lines) >= 4:
            leak_summary = "\n".join(lines[:4])
        else:
            leak_summary = "\n".join(lines)
    else:
        leak_summary = "LEAK SUMMARY not found"
    return leak_summary

def execute_redis_transaction(commands, timeout=15):
    # Prepare the transaction commands
    transaction_commands = ['MULTI'] + commands + ['EXEC']
    
    # Join all commands into a single string, separated by newlines
    combined_command = '\n'.join(transaction_commands)
    
    # Use echo to pipe the commands into redis-cli
    full_command = f"echo '{combined_command}' | redis-cli -p 1999"
    
    output, error = run_command(full_command, timeout)
    
    print(f"Debug - Full command: {full_command}")
    print(f"Debug - Output: {output} {error}")
    
    if error:
        return [{'command': combined_command, 'error': error}], None
    
    # Parse the output to separate results for each command
    lines = output.strip().split('\n')
    results = []
    for i, line in enumerate(lines):
        if i < len(transaction_commands):
            results.append({'command': transaction_commands[i], 'output': line})
    
    # The last line contains the result of the transaction
    transaction_result = lines[-1] if lines else None

    return results, transaction_result

def run_test_group(command_group, iterations):
    group_name = command_group['name']
    log_file = f"envoy_valgrind_{group_name}_xmem_read.log"

    envoy_command = f"valgrind --leak-check=full --show-leak-kinds=all --log-file={log_file} ./bazel-bin/source/exe/envoy-static -c envoy.yaml --log-level debug > build_output.log 2>&1"
    subprocess.Popen(envoy_command, shell=True)

    try:
        envoy_pid = wait_for_envoy()
        print(f"Envoy started with PID: {envoy_pid}")
    except TimeoutError as e:
        print(f"Error: {e}")
        return {'group': group_name, 'leak_summary': str(e)}

    try:
        if not check_redis_ping():
            return {'group': group_name, 'leak_summary': "Error: Redis did not respond in time"}
    except TimeoutError as e:
        print(f"Error: {e}")
        return {'group': group_name, 'leak_summary': str(e)}

    print(f"\nExecuting command group: {group_name}")
    
    all_results = []
    all_transaction_results = []
    
    for i in range(iterations):
        print(f"Iteration {i+1}/{iterations}")
        results, transaction_result = execute_redis_transaction(command_group['commands'])
        all_results.append(results)
        all_transaction_results.append(transaction_result)

    try:
        kill_envoy()
    except TimeoutError as e:
        print(f"Error: {e}")
        return {'group': group_name, 'leak_summary': str(e)}

    leak_summary = parse_log_file(log_file)

    return {
        'group': group_name, 
        'results': all_results, 
        'transaction_results': all_transaction_results, 
        'leak_summary': leak_summary
    }

def analyze_memory_leak_report(file_path='memory_leak_report_for_transaction.txt'):
    with open(file_path, 'r') as file:
        content = file.read()

    definitely_lost_lines = re.findall(r'definitely lost: .*', content)

    if not definitely_lost_lines:
        return "Failed: No 'definitely lost' information found in the report."

    all_zero = all('0 bytes in 0 blocks' in line for line in definitely_lost_lines)

    if all_zero:
        return "Passed: No memory leaks detected."
    else:
        return "Failed: Memory leak is identified. Scan through the report for more details."

def main():
    redis_command_groups = [
        {
            'name': 'transaction_string_operations',
            'commands': [
                "SET {key}1 'Hello'",
                "GET {key}1",
                "APPEND {key}1 ' World'",
                "STRLEN {key}1",
                "TTL {key}1",
                "PTTL {key}2",
                "GET {key}1",
                "SETRANGE {key}1 6 'Redis'",
                "GET {key}1",
                "GETRANGE {key}1 0 4",
                "INCR {key}counter",
                "INCRBY {key}counter 5",
                "INCRBYFLOAT {key}counter 1.5",
                "INCRBYFLOAT {key}counter 1.5",
                "DECR {key}counter",
                "DECRBY {key}counter 2",
                "SETBIT {key}bitmap 7 1",
                "GETBIT {key}bitmap 7",
                "BITCOUNT {key}bitmap",
                "BITPOS {key}bitmap 1",
            ]
        },
        {
            'name': 'transaction_list_operations',
            'commands': [
                "LPUSH {mylist}1 item1 item2",
                "RPUSH {mylist}1 item3 item4",
                "LPUSHX {mylist}2 item5",
                "RPUSHX {mylist}2 item6",
                "LLEN {mylist}1",
                "LRANGE {mylist}1 0 -1",
                "LPOP {mylist}1",
                "RPOP {mylist}1",
                "LINDEX {mylist}1 0",
                "LREM {mylist}1 2 'item3'",
                "LTRIM {mylist}1 0 1",
                "SORT {mylist}1 alpha",
                "RPOPLPUSH {mylist}1 {mylist}2"
            ]
        },
        {
            'name': 'transaction_set_operations',
            'commands': [
                "SADD {myset}1 member1 member2 member3",
                "SCARD {myset}1",
                "SMEMBERS {myset}1",
                "SISMEMBER {myset}1 member1",
                "SREM {myset}1 member2",
                "SRANDMEMBER {myset}1 2",
                "SPOP {myset}1",
                "SADD {myset}1 member4",
                "SMOVE {myset}1 {myset}2 member4",
                "SMEMBERS {myset}2",
                "SDIFF {myset}1 {myset}2",
                "SDIFFSTORE {myset}3 {myset}1 {myset}2",
                "SINTER {myset}1 {myset}2",
                "SINTERSTORE {myset}4 {myset}1 {myset}2",
                "SMEMBERS {myset}4",
                "SUNION {myset}1 {myset}2",
                "SUNIONSTORE {myset}5 {myset}1 {myset}2",
                "SMEMBERS {myset}5"
            ]
        },
        {
            'name': 'transaction_hash_operations',
            'commands': [
                "HSET myhash field1 'value1' field2 'value2'",
                "HSETNX myhash field3 'value3'",
                "HGET myhash field1",
                "HMSET myhash field4 'value4' field5 'value5'",
                "HMGET myhash field1 field2 field3",
                "HGETALL myhash",
                "HDEL myhash field2",
                "HEXISTS myhash field1",
                "HEXISTS myhash field2",
                "HKEYS myhash",
                "HVALS myhash",
                "HLEN myhash",
                "HINCRBY myhash field6 5",
                "HINCRBYFLOAT myhash field7 1.5",
                "HSCAN myhash 0"
            ]
        },
        {
            'name': 'transaction_sorted_set_operations',
            'commands': [
                "ZADD {myzset}1 1 'one' 2 'two' 3 'three'",
                "ZRANGE {myzset}1 0 -1 WITHSCORES",
                "ZREVRANGE {myzset}1 0 -1 WITHSCORES",
                "ZRANK {myzset}1 'two'",
                "ZREVRANK {myzset}1 'two'",
                "ZCOUNT {myzset}1 1 2",
                "ZINCRBY {myzset}1 1 'one'",
                "ZREM {myzset}1 'two'",
                "ZRANGEBYSCORE {myzset}1 1 3",
                "ZREVRANGEBYSCORE {myzset}1 3 1",
                "ZREMRANGEBYRANK {myzset}1 0 0",
                "ZREMRANGEBYSCORE {myzset}1 1 2",
                "ZCARD {myzset}1",
                "ZSCORE {myzset}1 'three'",
                "ZUNIONSTORE {myzset}union 2 {myzset}1 {myzset}2",
                "ZINTERSTORE {myzset}inter 2 {myzset}1 {myzset}2",
                "ZSCAN {myzset}1 0",
                "ZRANGEBYLEX {myzset}1 - +",
                "ZLEXCOUNT {myzset}1 - +",
                "ZREMRANGEBYLEX {myzset}1 - +"
            ]
        },
        {
            'name': 'transaction_hyperLogLog_operations',
            'commands': [
                "PFADD {myhll}1 a b c d",
                "PFCOUNT {myhll}1",
                "PFADD {myhll}2 c d e f",
                "PFMERGE {myhll}3 {myhll}1 {myhll}2",
                "PFCOUNT {myhll}3"
            ]
        },
        {
            'name': 'transaction_geo_operations',
            'commands': [
                "GEOADD locations 13.361389 38.115556 'Palermo' 15.087269 37.502669 'Catania'",
                "GEODIST locations 'Palermo' 'Catania'",
                "GEOHASH locations 'Palermo'",
                "GEOPOS locations 'Palermo'",
                "GEORADIUS locations 15 37 100 km",
                "GEORADIUSBYMEMBER locations 'Palermo' 200 km"
            ]
        },
        {
            'name': 'transaction_stream_operations',
            'commands': [
                "XADD mystream * name 'abcd' age '20'",
                "XLEN mystream",
                "XRANGE mystream - +",
                "XREVRANGE mystream + - COUNT 1",
                "XPENDING mystream mygroup - + 10",
                "XGROUP CREATE mystream mygroup $",
                "XPENDING mystream mygroup - + 10",
                "XREAD COUNT 1 STREAMS mystream 0-0",
                "XREADGROUP GROUP mygroup consumer COUNT 1 STREAMS mystream >",
                "XREADGROUP GROUP mygroup consumer COUNT 1 STREAMS mystream 0",
                "XACK mystream mygroup 0",
                "XPENDING mystream mygroup - + 10",
                "XADD mystream * name 'efgh' age '30'",
                "XINFO STREAM mystream",
                "XINFO GROUPS mystream",
                "XTRIM mystream MAXLEN 1000",
                "XGROUP DESTROY mystream mygroup",
                "XGROUP DESTROY mystream mygroup",
                "XADD mystream 2345678904567 hello world",
                "XDEL mystream 2345678904567-0",
                "XDEL mystream 2345678904567-0"
            ]
        },
        {
            'name': 'transaction_server_operations',
            'commands': [
                "PING",
                "ECHO \"Hello World\"",
                "TIME",
                "CLIENT LIST",
                "CLIENT SETNAME myclient",
                "CLIENT GETNAME"
            ]
        },
        {
            'name': 'transaction_keyspace_operations',
            'commands': [
                "SET {mykey}1 myvalue",
                "TYPE {mykey}1",
                "EXISTS {mykey}1",
                "DEL {mykey}1",
                "UNLINK {mykey}1",
                "SET {mykey}1 myvalue",
                "UNLINK {mykey}1",
                "SET {mykey}1 myvalue",
                "EXPIRE {mykey}1 100",
                "PERSIST {mykey}1",
                "TTL {mykey}1",
                "SET {mykey}1 myvalue",
                "RENAME {mykey}1 {mykey}3",
                "GET {mykey}3"
            ]
        },
        {
            'name': 'transaction_copy_operation',
            'commands': [
                "DEL {mykey}1 {mykey}2",
                "MSET {mykey}1 value1 {mykey}2 value2",
                "MGET {mykey}1 {mykey}2",
                "COPY {mykey}1 {mykey}2",
                "MGET {mykey}1 {mykey}2",
                "COPY {mykey}1 {mykey}2 REPLACE",
                "MGET {mykey}1 {mykey}2"
            ]
        },
        {
            'name': 'transaction_blocking_operations',
            'commands': [
                "del {mylist}1 {mylist}2",
                "del {mylist}_zset1 {mylist}_zset2",
                "lpush {mylist}1 1 3 5 7 9",
                "rpush {mylist}2 2 4 6 8 10",
                "BLPOP {mylist}1 1000",
                "BRPOP {mylist}2 1000",
                "BRPOPLPUSH {mylist}1 {mylist}2 100",
                "ZADD {mylist}_zset1 1 one 3 three 5 five 7 seven 9 nine",
                "ZADD {mylist}_zset2 2 two 4 four 6 six 8 eight 10 ten",
                "BZPOPMIN {mylist}_zset1 1000",
                "BZPOPMAX {mylist}_zset2 1000",
                "BLPOP {mylist}_zset1 0",
                "BRPOP {mylist}_zset2 0",
                "BRPOPLPUSH {mylist}1 {mylist}2 0",
                "BZPOPMIN {mylist}_zset1 0",
                "BZPOPMAX {mylist}_zset2 0",
                "BLMOVE {mylist}2 {mylist}1 LEFT LEFT 1000",
                "BLMOVE {mylist}2 {mylist}1 LEFT RIGHT 1000",
                "BLMOVE {mylist}2 {mylist}1 RIGHT LEFT 1000",
                "BLMOVE {mylist}2 {mylist}1 RIGHT RIGHT 1000",
                "LRANGE {mylist}1 0 -1",
                "LRANGE {mylist}2 0 -1",
                "BLMOVE {mylist}1 {mylist}2 LEFT LEFT 0",
                "BLMOVE {mylist}1 {mylist}2 LEFT RIGHT 0",
                "BLMOVE {mylist}1 {mylist}2 RIGHT LEFT 0",
                "BLMOVE {mylist}1 {mylist}2 RIGHT RIGHT 0",
                "LRANGE {mylist}1 0 -1",
                "LRANGE {mylist}2 0 -1"
            ]
        },
        {
            'name': 'transaction_xread_xreadgroup',
            'commands': [
                "DEL mystream",
                "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 10000 STREAMS mystream 0",
                "XGROUP CREATE mystream mygroup $",
                "XADD mystream * field1 value1",
                "XREAD BLOCK 100 STREAMS mystream 0",
                "XREAD count 1 BLOCK 100 STREAMS mystream 0",
                "XREAD count 1 BLOCK 0 STREAMS mystream 0",
                "XREAD count -1 BLOCK 100 STREAMS mystream 0",
                "XREAD count -1 BLOCK 0 STREAMS mystream 0",
                "XADD mystream * field2 value2",
                "XGROUP CREATE mystream mygroup $",
                "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 10000 STREAMS mystream 0",
                "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 10000 STREAMS mystream >",
                "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 10000 STREAMS mystream 0",
                "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 0 STREAMS mystream 0",
                "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 0 STREAMS mystream >",
                "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 0 STREAMS mystream 0",
                
            ]
        }
    ]

    iterations = 100
    report = []

    for command_group in redis_command_groups:
        print(f"\nRunning test group: {command_group['name']}")
        results = run_test_group(command_group, iterations)
        report.append(results)

    # Write report
    with open('memory_leak_report_for_transaction.txt', 'w') as f:
        for item in report:
            f.write(f"Command Group: {item['group']}\n")
            for iteration, (results, transaction_result) in enumerate(zip(item['results'], item['transaction_results']), 1):
                f.write(f"Iteration {iteration}:\n")
                f.write("Commands executed:\n")
                for result in results:
                    f.write(f"  - {result['command']}: {result.get('output', result.get('error', 'N/A'))}\n")
                f.write(f"Transaction Result: {transaction_result}\n\n")
            f.write(f"Leak Summary:\n{item['leak_summary']}\n\n")

    print("\nTesting completed. Results written to memory_leak_report_for_transaction.txt")

    # Analyze the memory leak report
    analysis_result = analyze_memory_leak_report()
    print(f"\nMemory Leak Analysis Result: {analysis_result}\n\n")

if __name__ == "__main__":
    main()