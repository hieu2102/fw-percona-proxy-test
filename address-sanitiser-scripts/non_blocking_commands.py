import subprocess
import time
import re
import sys

def run_command(command):
    process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output, error = process.communicate()
    return output.decode('utf-8'), error.decode('utf-8')

def start_envoy():
    command = "./bazel-bin/source/exe/envoy-static -c envoy.yaml > envoy_logs.txt 2>&1 &"
    subprocess.Popen(command, shell=True)
    print("Started Envoy process")

def wait_for_envoy(timeout=600):
    start_time = time.time()
    while True:
        output, error = run_command("ps -ef | grep 'envoy-static'")
        print(f"Debug - PS output:{output}")

        if "envoy-static" in output:
            # Simplified regex that's more flexible
            pid_match = re.search(r'\s*root\s+(\d+)\s+.*envoy-static', output)
            if pid_match:
                pid = pid_match.group(1)
                print(f"Debug - Envoy PID found: {pid}")
                return pid
            else:
                print("Debug - 'envoy-static' found in output, but couldn't extract PID")
                print(f"Debug - Regex didn't match. Raw output: {output}")
        else:
            print("Debug - 'envoy-static' not found in output")

        if time.time() - start_time > timeout:
            print(f"Debug - Last PS output before timeout:{output}")
            raise TimeoutError("Timed out waiting for Envoy to start")

        time.sleep(1)

def check_redis_ping(timeout=600):
    start_time = time.time()
    while True:
        output, error = run_command("redis-cli -p 1999 PING")
        if "PONG" in output:
            print("Redis is responsive")
            return True
        if time.time() - start_time > timeout:
            raise TimeoutError("Timed out waiting for Redis to respond")
        time.sleep(1)

def check_envoy_and_redis():
    try:
        envoy_pid = wait_for_envoy()
        print(f"Envoy is running with PID: {envoy_pid}")
        redis_responsive = check_redis_ping()
        return redis_responsive
    except TimeoutError as e:
        print(f"Error: {e}")
        return False

def run_redis_commands(redis_command_groups):
    report = []
    for group in redis_command_groups:
        for command in group['commands']:
            if not check_envoy_and_redis():
                report.append(f"{group['name']} - Failed")
                print("\ ".join(report))
                sys.exit(1)

            output, error = run_command(f"redis-cli -p 1999 {command}")
            if error:
                report.append(f"{group['name']} - Failed")
                print("\ ".join(report))
                sys.exit(1)
            else:
                report.append(f"{group['name']} - Success")

    report.append("Test completed")
    print("\ ".join(report))

# Redis command groups
redis_command_groups = [
        {
            'name': 'xadd',
            'commands': [
                'xadd order_stream * order_id 12345 product_id 789 quantity 2',
                'xadd event_log MAXLEN ~ 1000 * user_id 1001 action "login" timestamp 1623456789',
                'xadd notification_stream NOMKSTREAM * user_id 2002 message "New friend request" sender_id 3003',
                'xadd sensor_data MINID ~ 1623456000000 * sensor_id 4004 temperature 22.5 humidity 45',
                'xadd audit_log LIMIT 1000 * admin_id 5005 action "update_user" target_user_id 6006'
            ]
        },
        {
            'name': 'xrange',
            'commands': [
                'xrange order_stream - +',
                'xrange event_log - + COUNT 5',
                'xrange sensor_data 1623456000000-0 + COUNT 10'
            ]
        },
        {
            'name': 'xrevrange',
            'commands': [
                'xrevrange notification_stream + - COUNT 5',
                'xrevrange audit_log + - COUNT 10',
                'xrevrange order_stream + 1623456000000-0 COUNT 5'
            ]
        },
        {
            'name': 'xlen',
            'commands': [
                'xlen event_log'
            ]
        },
        {
            'name': 'xdel',
            'commands': [
                'xdel order_stream 1623456789123-0',
                'xdel sensor_data 1623456789123-0 1623456789124-0 1623456789125-0'
            ]
        },
        {
            'name': 'xtrim',
            'commands': [
                'xtrim audit_log MAXLEN 1000',
                'xtrim event_log MAXLEN ~ 1000',
                'xtrim notification_stream MINID 1623456000000-0',
                'xtrim sensor_data MINID ~ 1623456000000-0 LIMIT 500'
            ]
        },
        {
            'name': 'xgroup',
            'commands': [
                'xgroup create order_stream order_processors $',
                'xgroup createconsumer order_stream order_processors worker1',
                'xgroup setid notification_stream notification_handlers $',
                'xgroup destroy sensor_data sensor_analyzers',
                'xgroup delconsumer audit_log audit_reviewers admin1',
                'xgroup CREATE event_log event_handlers $ MKSTREAM',
                'xgroup SETID order_stream order_processors $ ENTRIESREAD 100'
            ]
        },
        {
            'name': 'xreadgroup',
            'commands': [
                'xreadgroup GROUP order_processors worker1 COUNT 10 STREAMS order_stream ">"',
                'xreadgroup GROUP notification_handlers mobile_app BLOCK 5000 COUNT 10 STREAMS notification_stream ">"',
                'xreadgroup GROUP sensor_analyzers analyzer1 NOACK STREAMS sensor_data ">"',
                'xreadgroup GROUP event_handlers web_server COUNT 10 STREAMS event_log1 event_log2 "> >"',
                'xreadgroup GROUP audit_reviewers admin2 COUNT 10 STREAMS audit_log 0-0'
            ]
        },
        {
            'name': 'xpending',
            'commands': [
                'xpending order_stream order_processors',
                'xpending notification_stream notification_handlers - + 10',
                'xpending sensor_data sensor_analyzers - + 10 analyzer1',
                'xpending audit_log audit_reviewers IDLE 3600000 - + 10 admin1'
            ]
        },
        {
            'name': 'xclaim',
            'commands': [
                'xclaim order_stream order_processors worker2 3600000 1623456789123-0',
                'xclaim notification_stream notification_handlers mobile_app 3600000 1623456789123-0 1623456789124-0 JUSTID',
                'xclaim sensor_data sensor_analyzers analyzer2 3600000 1623456789123-0 FORCE IDLE 7200000',
                'xclaim audit_log audit_reviewers admin2 3600000 1623456789123-0 RETRYCOUNT 5 TIME 1623456789'
            ]
        },
        {
            'name': 'xautoclaim',
            'commands': [
                'xautoclaim order_stream order_processors worker3 3600000 0-0 COUNT 10',
                'xautoclaim notification_stream notification_handlers mobile_app 3600000 0-0 COUNT 10 JUSTID'
            ]
        },
        {
            'name': 'sadd',
            'commands': [
                'sadd active_users user1001 user1002 user1003',
                'sadd product_categories electronics home_appliances'
            ]
        },
        {
            'name': 'smembers',
            'commands': [
                'smembers active_users'
            ]
        },
        {
            'name': 'srem',
            'commands': [
                'srem active_users user1001',
                'srem product_categories electronics home_appliances'
            ]
        },
        {
            'name': 'smismember',
            'commands': [
                'smismember active_users user1002 user1003 user1004'
            ]
        },
        {
            'name': 'sunion',
            'commands': [
                'sunion online_users offline_users',
                'sunion premium_products regular_products sale_products'
            ]
        },
        {
            'name': 'sdiff',
            'commands': [
                'sdiff all_users banned_users',
                'sdiff all_products out_of_stock_products discontinued_products'
            ]
        },
        {
            'name': 'sinter',
            'commands': [
                'sinter active_users premium_users',
                'sinter electronics_products discount_products in_stock_products'
            ]
        },
        {
            'name': 'scan',
            'commands': [
                'scan 0',
                'scan 0 MATCH user:* COUNT 100',
                'scan 0 TYPE string COUNT 50',
                'scan 0 MATCH product:* TYPE hash COUNT 200'
            ]
        },
        {
            'name': 'sunionstore',
            'commands': [
                'sunionstore all_active_users today_active_users yesterday_active_users',
                'sunionstore all_available_products in_stock_products pre_order_products upcoming_products'
            ]
        },
        {
            'name': 'sdiffstore',
            'commands': [
                'sdiffstore users_to_reactivate all_users active_users',
                'sdiffstore exclusive_products all_products regular_products sale_products'
            ]
        },
        {
            'name': 'sinterstore',
            'commands': [
                'sinterstore vip_active_users vip_users active_users',
                'sinterstore discounted_electronics electronics_products sale_products'
            ]
        },
        {
            'name': 'zunionstore',
            'commands': [
                'zunionstore total_sales 2 daily_sales weekly_sales WEIGHTS 1 7',
                'zunionstore overall_scores 3 exam1_scores exam2_scores exam3_scores AGGREGATE MAX'
            ]
        },
        {
            'name': 'zinterstore',
            'commands': [
                'zinterstore common_high_scores 2 game1_scores game2_scores WEIGHTS 2 3',
                'zinterstore top_products 3 electronics_sales home_appliances_sales fashion_sales AGGREGATE MIN'
            ]
        },
        {
            'name': 'pfmerge',
            'commands': [
                'pfmerge daily_unique_users hourly_unique_users_1 hourly_unique_users_2',
                'pfmerge weekly_unique_visitors monday_visitors tuesday_visitors wednesday_visitors'
            ]
        },
        {
            'name': 'georadius',
            'commands': [
                'georadius restaurants 13.361389 38.115556 5 km WITHDIST',
                'georadius gas_stations 15.087269 37.502669 10 km WITHCOORD COUNT 3 ASC',
                'georadius hotels 12.758489 38.788135 20 km WITHDIST WITHCOORD WITHHASH COUNT 5 DESC STORE nearby_hotels'
            ]
        },
        {
            'name': 'georadiusbymember',
            'commands': [
                'georadiusbymember restaurants "Pizza Palace" 2 km WITHDIST',
                'georadiusbymember hotels "Grand Hotel" 5 km WITHCOORD COUNT 3 ASC',
                'georadiusbymember attractions "Colosseum" 3 km WITHDIST WITHCOORD WITHHASH COUNT 5 DESC STORE nearby_attractions'
            ]
        },
        {
            'name': 'pubsub',
            'commands': [
                'pubsub channels',
                'pubsub channels user:*:notifications',
                'pubsub numsub user_notifications system_alerts',
                'pubsub numpat'
            ]
        },
        {
            'name': 'brpoplpush',
            'commands': [
                'lpush pending_tasks "task1"'
                'lpush notification_queue "notification1"'
                'brpoplpush pending_tasks active_tasks 0',
                'brpoplpush notification_queue sent_notifications 5'
            ]
        },
        {
            'name': 'bzpopmax',
            'commands': [
                'zadd priority_queue 1 "priority_task1"'
                'zadd task_queue1 1 "task1"'
                'zadd task_queue2 2 "task2"'
                'bzpopmax priority_queue 0',
                'bzpopmax task_queue1 task_queue2 5'
            ]
        },
        {
            'name': 'bzpopmin',
            'commands': [
                'zadd priority_queue 1 "priority_task1"'
                'zadd task_queue1 1 "task1"'
                'zadd task_queue2 2 "task2"'
                'bzpopmin priority_queue 0',
                'bzpopmin task_queue1 task_queue2 5'
            ]
        },
        {
            'name': 'blpop',
            'commands': [
                'lpush job_queue "job1"'
                'lpush queue1 "item1"'
                'lpush queue2 "item2"'
                'blpop job_queue 0',
                'blpop queue1 queue2 5'
            ]
        },
        {
            'name': 'brpop',
            'commands': [
                'rpush job_queue "job1"'
                'rpush queue1 "item1"'
                'rpush queue2 "item2"'
                'brpop job_queue 0',
                'brpop queue1 queue2 5'
            ]
        },
        {
            'name': 'script',
            'commands': [
                'script load "return redis.call(\'get\',KEYS[1])"',
                'script exists a42059b356c875f0717db19a51f6aaca9ae659ea',
                'script flush',
                'script kill'
            ]
        },
        {
            'name': 'flushall',
            'commands': [
                'flushall',
                'flushall ASYNC'
            ]
        },
        {
            'name': 'keys',
            'commands': [
                'keys *',
                'keys user:*'
            ]
        },
        {
            'name': 'slowlog',
            'commands': [
                'slowlog get',
                'slowlog get 10',
                'slowlog len',
                'slowlog reset'
            ]
        },
        {
            'name': 'config',
            'commands': [
                'config get *',
                'config get maxmemory',
                'config set maxmemory 2GB',
                'config resetstat'
            ]
        },
        {
            'name': 'client',
            'commands': [
                'client list',
                'client getname',
                'client setname web-server-1',
                'client kill 127.0.0.1:52500',
                'client pause 5000'
            ]
        },
        {
            'name': 'info',
            'commands': [
                'info',
                'info memory'
            ]
        },
        {
            'name': 'cluster',
            'commands': [
                'cluster info',
                'cluster nodes',
                'cluster slots',
                'cluster keyslot user:1001'
            ]
        },
        {
            'name': 'select',
            'commands': [
                'select 0',
                'select 1'
            ]
        },
        {
            'name': 'hello',
            'commands': [
                'hello 2',
                'hello 3 AUTH admin StrongPassword123',
                'hello 3 SETNAME analytics-service'
            ]
        },
        {
            'name': 'unwatch',
            'commands': [
                'unwatch'
            ]
        },
        {
            'name': 'rename',
            'commands': [
                'rename old_key new_key'
            ]
        },
        {
            'name': 'getdel',
            'commands': [
                'getdel session:token:1001'
            ]
        },
        {
            'name': 'getex',
            'commands': [
                'getex session:user:1001',
                'getex cache:product:5001 EX 3600',
                'getex rate_limit:ip:192.168.1.1 PX 100000',
                'getex temporary_flag EXAT 1640995200',
                'getex auth_token PXAT 1640995200000',
                'getex persistent_key PERSIST'
            ]
        },
        {
            'name': 'sort',
            'commands': [
                'sort user_scores',
                'sort product_prices DESC',
                'sort usernames ALPHA',
                'sort top_scores LIMIT 0 5',
                'sort user_ids BY user:*->age',
                'sort user_ids GET user:*->name',
                'sort product_ids STORE sorted_products'
            ]
        },
        {
            'name': 'zmscore',
            'commands': [
                'zmscore leaderboard player1 player2 player3'
            ]
        },
        {
            'name': 'msetnx',
            'commands': [
                'msetnx user:1001:name "John Doe" user:1001:email "john@example.com"'
            ]
        },
        {
            'name': 'substr',
            'commands': [
                'substr user:1001:name 0 3'
            ]
        },
        {
        'name': 'zrangestore',
        'commands': [
            'zrangestore top_scores all_scores 0 -1',
            'zrangestore high_value_products product_prices 1000 +inf BYSCORE',
            'zrangestore recent_logins user_last_login 0 -1 REV',
            'zrangestore top_10_expensive products 0 -1 BYSCORE REV LIMIT 0 10'
        ]
        },
        {
            'name': 'zunion',
            'commands': [
                'zunion 2 daily_sales weekly_sales',
                'zunion 2 product_views product_purchases WEIGHTS 1 5',
                'zunion 3 exam1_scores exam2_scores exam3_scores AGGREGATE MAX'
            ]
        },
        {
            'name': 'zdiff',
            'commands': [
                'zdiff 2 all_users active_users',
                'zdiff 3 all_products in_stock_products discontinued_products WITHSCORES'
            ]
        },
        {
        'name': 'xinfo',
        'commands': [
            'xinfo stream mystream',
            'xinfo stream mystream full',
            'xinfo groups mystream',
            'xinfo consumers mystream mygroup'
        ]
        },
        {
            'name': 'sunionstore',
            'commands': [
                'sunionstore destination key1 key2',
                'sunionstore destination key1 key2 key3'
            ]
        },
        {
            'name': 'smismember',
            'commands': [
                'smismember myset member1 member2 member3'
            ]
        },
        {
            'name': 'hrandfield',
            'commands': [
                'hrandfield myhash',
                'hrandfield myhash 2',
                'hrandfield myhash -5',
                'hrandfield myhash 3 withvalues'
            ]
        },
        {
            'name': 'geosearchstore',
            'commands': [
                'geosearchstore destination source fromlon 13.361389 fromlat 38.115556 bybox 400 400 m',
                'geosearchstore destination source frommember Palermo byradius 100 km',
                'geosearchstore destination source fromlonlat 13.361389 38.115556 byradius 100 km asc count 3 storedist'
            ]
        },
        # {
        #     'name': 'xreadgroup',
        #     'commands': [
        #         'xreadgroup group mygroup consumer1 streams mystream >',
        #         'xreadgroup group mygroup consumer1 count 2 streams mystream >',
        #         'xreadgroup group mygroup consumer1 block 2000 streams mystream >',
        #         'xreadgroup group mygroup consumer1 noack streams mystream >'
        #     ]
        # },
        {
            'name': 'zdiffstore',
            'commands': [
                'zdiffstore destination 2 zset1 zset2',
                'zdiffstore destination 3 zset1 zset2 zset3'
            ]
        },
        {
            'name': 'geosearch',
            'commands': [
                'geosearch sicily fromlon 13.361389 fromlat 38.115556 bybox 400 400 m',
                'geosearch sicily frommember Palermo byradius 100 km',
                'geosearch sicily fromlonlat 13.361389 38.115556 byradius 100 km asc count 3 withdist withcoord withhash'
            ]
        },
        {
            'name': 'randomkey',
            'commands': [
                'randomkey'
            ]
        },
        {
            'name': 'zinter',
            'commands': [
                'zinter 2 zset1 zset2',
                'zinter 2 zset1 zset2 withscores',
                'zinter 3 zset1 zset2 zset3 weights 1 2 3 aggregate max'
            ]
        },
        {
            'name': 'blmove',
            'commands': [
                'blmove source destination left right 0',
                'blmove source destination right left 5'
            ]
        },
        {
            'name': 'zrandmember',
            'commands': [
                'zrandmember myset',
                'zrandmember myset 2',
                'zrandmember myset -5',
                'zrandmember myset 3 withscores'
            ]
        },
        {
            'name': 'bitop',
            'commands': [
                'bitop and destkey srckey1 srckey2 srckey3',
                'bitop or destkey srckey1 srckey2 srckey3',
                'bitop xor destkey srckey1 srckey2 srckey3',
                'bitop not destkey srckey'
            ]
        },
        {
            'name': 'lpos',
            'commands': [
                'lpos mylist element',
                'lpos mylist element rank 2',
                'lpos mylist element count 2',
                'lpos mylist element maxlen 1000'
            ]
        },
        {
            'name': 'renamenx',
            'commands': [
                'renamenx key newkey'
            ]
        },
        {
            'name': 'xclaim',
            'commands': [
                'xclaim mystream mygroup consumer 3600000 ID1 ID2 ID3',
                'xclaim mystream mygroup consumer 3600000 ID1 ID2 ID3 idle 1000',
                'xclaim mystream mygroup consumer 3600000 ID1 ID2 ID3 time 1609459200000',
                'xclaim mystream mygroup consumer 3600000 ID1 ID2 ID3 retrycount 5',
                'xclaim mystream mygroup consumer 3600000 ID1 ID2 ID3 force',
                'xclaim mystream mygroup consumer 3600000 ID1 ID2 ID3 justid'
            ]
        }
    # ... (include other command groups here)
]

# Main execution
if __name__ == "__main__":
    start_envoy()
    if check_envoy_and_redis():
        run_redis_commands(redis_command_groups)
    else:
        print("Failed to start Envoy or connect to Redis")
        sys.exit(1)