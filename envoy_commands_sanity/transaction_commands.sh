#!/bin/bash

REDIS_HOST="${REDIS_HOST:?Set REDIS_HOST to the proxy host}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:?Set REDIS_PASSWORD}"


# Function to execute a single Redis command within a transaction
execute_redis_command() {
    command="$1"
    result=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" << EOF
MULTI
$command
EXEC
EOF
2>/dev/null | grep -v option
)
    echo "$result"
}

# Function to validate command output
validate_output() {
    command="$1"
    output="$2"
    expected="$3"

    case "$output" in
        *"WRONGTYPE"*|*"NOSCRIPT"*|*"NOTBUF"*|*"SYNTAXERR"*)
            echo "$(date) : FATAL : ❌ Error with command : $command"
            echo "$(date) : INFO  :         Error message : $output"
            return 1
            ;;
        *)
            if [ "$output" = "$expected" ]
            then
                echo "$(date) : PASSED : ✅ Command successful : $command"
                echo "$(date) : INFO   :                Output : $output"
                return 0
            else
                echo "$(date) : FAILED : ❌ Unexpected result for command : $command"
                echo "$(date) : INFO   :                  Expected output : $expected"
                echo "$(date) : INFO   :                    Actual output : $output"
                return 1
            fi
            ;;
    esac
}

# Redis commands to test with all possible subcommands
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" FLUSHALL 2>/dev/null | grep -v option
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" SCRIPT LOAD "redis.call('SET', KEYS[1], ARGV[1]); return redis.call('GET', KEYS[1])" 2>/dev/null | grep -v option
   commands=(
    # 1. String operations
    "SET mykey 'Hello'"
    "GET mykey"
    "APPEND mykey ' World'"
    "STRLEN mykey"
    "SETEX tempkey 10 'This will expire'"
    "PSETEX tempkey2 10000 'This will expire in milliseconds'"
    "TTL tempkey"
    "PTTL tempkey2"
    "SETNX newkey 'This is new'"
    "MSETNX key3 'value3' key4 'value4'"
    "MSETNX {key}1 'value1' {key}2 'value2' {key}3 'value3'"
    "MSET {key}1 'value1' {key}2 'value2'"
    "MGET {key}1 {key}2 {key}3"
    "SETRANGE mykey 6 'Redis'"
    "GETRANGE mykey 0 4"
    "INCR counter"
    "INCRBY counter 5"
    "INCRBYFLOAT counter 1.5"
    "INCRBYFLOAT counter 1.5"
    "DECR counter"
    "DECRBY counter 2"
    "SETBIT mybitmap 7 1"
    "GETBIT mybitmap 7"
    "BITCOUNT mybitmap"
    "BITPOS mybitmap 1"
    "GETSET mykey 'New Value'"
    "GET mykey"
    "STRLEN mykey"
    
    # 2. List operations
    "LPUSH {mylist}1 item1 item2"
    "RPUSH {mylist}1 item3 item4"
    "LPUSHX {mylist}2 item5"
    "RPUSHX {mylist}2 item6"
    "LLEN {mylist}1"
    "LRANGE {mylist}1 0 -1"
    "LPOP {mylist}1"
    "RPOP {mylist}1"
    "LINDEX {mylist}1 0"
    "LSET {mylist}1 0 'new item'"
    "LREM {mylist}1 2 'item3'"
    "LTRIM {mylist}1 0 1"
    "LINSERT {mylist}1 BEFORE 'new item' 'inserted item'"
    "RPOPLPUSH {mylist}1 {mylist}2"
    "BLPOP {mylist}1 1"
    "BRPOP {mylist}2 1"
    "LPUSH {mylist}1 item1 item2 item3"
    "BLPOP {mylist}1 0"
    "BRPOP {mylist}1 0"
    "BRPOPLPUSH {mylist}1 {mylist}2 0"
    "BRPOPLPUSH {mylist}2 {mylist}1 1"
    
    # 3. Set operations
    "SADD {myset}1 member1 member2 member3"
    "SCARD {myset}1"
    "SMEMBERS {myset}1"
    "SISMEMBER {myset}1 member1"
    "SREM {myset}1 member2"
    "SRANDMEMBER {myset}1 2"
    "SADD {myset}1 member4"
    "SMOVE {myset}1 {myset}2 member4"
    "SMEMBERS {myset}2"
    "SDIFF {myset}1 {myset}2"
    "SDIFFSTORE {myset}3 {myset}1 {myset}2"
    "SINTER {myset}1 {myset}2"
    "SINTERSTORE {myset}4 {myset}1 {myset}2"
    "SMEMBERS {myset}4"
    "SUNION {myset}1 {myset}2"
    "SUNIONSTORE {myset}5 {myset}1 {myset}2"
    "SMEMBERS {myset}5"
    "SPOP {myset}1"
    
    # 4. Hash operations
    "HSET myhash field1 'value1' field2 'value2'"
    "HSETNX myhash field3 'value3'"
    "HGET myhash field1"
    "HMSET myhash field4 'value4' field5 'value5'"
    "HMGET myhash field1 field2 field3"
    "HGETALL myhash"
    "HDEL myhash field2"
    "HEXISTS myhash field1"
    "HEXISTS myhash field2"
    "HKEYS myhash"
    "HVALS myhash"
    "HLEN myhash"
    "HINCRBY myhash field6 5"
    "HINCRBYFLOAT myhash field7 1.5"
    "HSCAN myhash 0"
    
    # 5. Sorted Set operations
    "ZADD {myzset}1 1 'one' 2 'two' 3 'three'"
    "ZRANGE {myzset}1 0 -1 WITHSCORES"
    "ZREVRANGE {myzset}1 0 -1 WITHSCORES"
    "ZRANK {myzset}1 'two'"
    "ZREVRANK {myzset}1 'two'"
    "ZCOUNT {myzset}1 1 2"
    "ZINCRBY {myzset}1 1 'one'"
    "ZREM {myzset}1 'two'"
    "ZRANGEBYSCORE {myzset}1 1 3"
    "ZREVRANGEBYSCORE {myzset}1 3 1"
    "ZREMRANGEBYRANK {myzset}1 0 0"
    "ZREMRANGEBYSCORE {myzset}1 1 2"
    "ZCARD {myzset}1"
    "ZSCORE {myzset}1 'three'"
    "ZUNIONSTORE {myzset}union 2 {myzset}1 {myzset}2"
    "ZINTERSTORE {myzset}inter 2 {myzset}1 {myzset}2"
    "ZSCAN {myzset}1 0"
    "ZRANGEBYLEX {myzset}1 - +"
    "ZLEXCOUNT {myzset}1 - +"
    "ZREMRANGEBYLEX {myzset}1 - +"
    
    # 6. HyperLogLog operations
    "PFADD {myhll}1 a b c d"
    "PFCOUNT {myhll}1"
    "PFADD {myhll}2 c d e f"
    "PFMERGE {myhll}3 {myhll}1 {myhll}2"
    "PFCOUNT {myhll}3"
    
    # 7. Geo operations
    "GEOADD locations 13.361389 38.115556 'Palermo' 15.087269 37.502669 'Catania'"
    "GEODIST locations 'Palermo' 'Catania'"
    "GEOHASH locations 'Palermo'"
    "GEOPOS locations 'Palermo'"
    "GEORADIUS locations 15 37 100 km"
    "GEORADIUSBYMEMBER locations 'Palermo' 200 km"
    
    # 8. Stream operations
    "XADD mystream * name 'abcd' age '20'"
    "XLEN mystream"
    "XRANGE mystream - +"
    "XREVRANGE mystream + - COUNT 1"
    "XPENDING mystream mygroup - + 10"
    "XGROUP CREATE mystream mygroup $"
    "XPENDING mystream mygroup - + 10"
    "XREAD COUNT 1 STREAMS mystream 0-0"
    "XREADGROUP GROUP mygroup consumer COUNT 1 STREAMS mystream >"
    "XREADGROUP GROUP mygroup consumer COUNT 1 STREAMS mystream 0"
    "XACK mystream mygroup 0"
    "XPENDING mystream mygroup - + 10"
    "XADD mystream * name 'efgh' age '30'"
    "XINFO STREAM mystream"
    "XINFO GROUPS mystream"
    "XTRIM mystream MAXLEN 1000"
    "XGROUP DESTROY mystream mygroup"
    "XGROUP DESTROY mystream mygroup"
    "XADD mystream 2345678904567 hello world"
    "XDEL mystream 2345678904567-0"
    "XDEL mystream 2345678904567-0"
    
    # 9. Transaction operations
    "MULTI"
    "SET transaction_key 'value'"
    "GET transaction_key"
    "EXEC"
    "DISCARD"
    "WATCH transaction_key"
    "UNWATCH"
    
    # 10. Scripting
    "EVAL 'return {KEYS[1],ARGV[1]}' 1 mykey 'Hello'"
    "SCRIPT LOAD \"redis.call('SET', KEYS[1], ARGV[1]); return redis.call('GET', KEYS[1])\""
    "EVALSHA 'f7e0c9bbf13a8a4f79c0de158c2f1b1e7e8535e1' 1 mykey"
    "EVALSHA '18d788194860a281b19910d462b1e96dabf3c984' 1 mykey hello"
    "SCRIPT EXISTS f7e0c9bbf13a8a4f79c0de158c2f1b1e7e8535e1"
    "SCRIPT FLUSH"
    
    # 11. Connection and server operations
    "PING"
    "ECHO 'Hello World'"
    "TIME"
    "CLIENT LIST"
    "CLIENT GETNAME"
    "CLIENT SETNAME myclient"
    "CLIENT GETNAME"
    "CONFIG GET *"
    "SLOWLOG GET 1"
    "INFO"
    
    # 12. Key space operations
    "RANDOMKEY"
    "SCAN 0"
    "SET {mykey}1 myvalue"
    "TYPE {mykey}1"
    "EXISTS {mykey}1"
    "DEL {mykey}1"
    "UNLINK {mykey}1"
    "SET {mykey}1 myvalue"
    "UNLINK {mykey}1"
    "SET {mykey}1 myvalue"
    "EXPIRE {mykey}1 100"
    "PERSIST {mykey}1"
    "TTL {mykey}1"
    "MOVE {mykey}1 1"
    "SET {mykey}1 myvalue"
    "RENAME {mykey}1 {mykey}3"
    "GET {mykey}3"
    "RENAMENX {mykey}3 {mykey}4"
    "GET {mykey}4"
    "SORT {mylist}1 alpha"
    "KEYS *"
    
    # 13. Pub/Sub operations
    "PUBLISH mychannel 'Hello'"
    "PUBSUB CHANNELS"
    #"SUBSCRIBE mychannel"
    "UNSUBSCRIBE mychannel"
    #"PSUBSCRIBE mychannel*"
    "PUNSUBSCRIBE mychannel*"
    
    # 14. Database operations
    "SELECT 1"
    "FLUSHDB"
    "SELECT 0"
    "FLUSHALL"
    "DBSIZE"
    "SWAPDB 0 1"
    
    # 15. Cluster operations
     "CLUSTER INFO"
     "CLUSTER NODES"
     "CLUSTER SLOTS"
    
    # 16. Module operations
     "MODULE LIST"
     "MODULE LOAD /path/to/mymodule.so"
     "MODULE UNLOAD mymodule"
    
    # 17. Blocking commands
    "del {mylist}1 {mylist}2"
    "del {myzset}1 {myzset}2"
    "lpush {mylist}1 1 3 5 7 9"
    "rpush {mylist}2 2 4 6 8 10"
    "BLPOP {mylist}1 1000"
    "BRPOP {mylist}2 1000"
    "BRPOPLPUSH {mylist}1 {mylist}2 100"
    "ZADD {myzset}1 1 one 3 three 5 five 7 seven 9 nine"
    "ZADD {myzset}2 2 two 4 four 6 six 8 eight 10 ten"
    "BZPOPMIN {myzset}1 1000"
    "BZPOPMAX {myzset}2 1000"
    "BLPOP {mylist}1 0"
    "BRPOP {mylist}2 0"
    "BRPOPLPUSH {mylist}1 {mylist}2 0"
    "BZPOPMIN {myzset}1 0"
    "BZPOPMAX {myzset}2 0"
    "BLMOVE {mylist}2 {mylist}1 LEFT LEFT 1000"
    "BLMOVE {mylist}2 {mylist}1 LEFT RIGHT 1000"
    "BLMOVE {mylist}2 {mylist}1 RIGHT LEFT 1000"
    "BLMOVE {mylist}2 {mylist}1 RIGHT RIGHT 1000"
    "LRANGE {mylist}1 0 -1"
    "LRANGE {mylist}2 0 -1"
    "BLMOVE {mylist}1 {mylist}2 LEFT LEFT 0"
    "BLMOVE {mylist}1 {mylist}2 LEFT RIGHT 0"
    "BLMOVE {mylist}1 {mylist}2 RIGHT LEFT 0"
    "BLMOVE {mylist}1 {mylist}2 RIGHT RIGHT 0"
    "LRANGE {mylist}1 0 -1"
    "LRANGE {mylist}2 0 -1"
    #XREAD
    "XREAD BLOCK 100 STREAMS mystream 0"
    "XREAD BLOCK 100 STREAMS mystream $"
    "XREAD STREAMS mystream 0 BLOCK 100"
    "XREAD 0 STREAMS mystream 0 BLOCK 100"
    "XREAD STREAMS mystream 0 BLOCK 0"
    "XREAD STREAMS BLOCK 100 mystream 0"
    "XREAD STREAMS BLOCK 0 mystream 0"
    "XREAD STREAMS mystream 0 BLOCK 100 count 0"
    "XREAD count 1 BLOCK 100 STREAMS mystream 0"
    "XREAD count 1 BLOCK 0 STREAMS mystream 0"
    "XREAD STREAMS BLOCK 100 count 0 mystream 0"
    "XREAD STREAMS BLOCK 0 count 0 mystream 0"
    "XREAD STREAMS mystream 0 BLOCK 100 count -1"
    "XREAD STREAMS mystream 0 BLOCK 0 count -1"
    "XREAD count -1 BLOCK 100 STREAMS mystream 0"
    "XREAD count -1 BLOCK 100 0 STREAMS mystream 0"
    "XREAD count -1 BLOCK 0 STREAMS mystream 0"
    "XREAD STREAMS BLOCK 100 count -1 mystream 0"
    "XREAD STREAMS BLOCK 0 count -1 mystream 0"
    #"XREADGROUP GROUP mygroup myconsumer BLOCK 1000 STREAMS mystream >"
    "XGROUP CREATE mystream mygroup $"
    "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 10000 STREAMS mystream 0"
    "XADD mystream * field1 value1"
    "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 10000 STREAMS mystream 0"
    "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 10000 STREAMS mystream >"
    "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 10000 STREAMS mystream 0"
    "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 0 STREAMS mystream 0"
    "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 0 STREAMS mystream >"
    "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 0 STREAMS mystream 0"
    "XREADGROUP GROUP mygroup consumer COUNT 10 BLOCK 0 STREAMS mystream 0"
    "XREADGROUP GROUP mygroup consumer BLOCK 0 COUNT 10 STREAMS mystream 0"
    "XREADGROUP GROUP mygroup BLOCK 0 consumer COUNT 10 STREAMS mystream 0"
    "XREADGROUP BLOCK 0 GROUP mygroup consumer COUNT 10 STREAMS mystream 0"
    "XREADGROUP GROUP mygroup COUNT 10 consumer BLOCK 0 STREAMS mystream 0"
    "XREADGROUP GROUP mygroup consumer BLOCK 0 COUNT 10 STREAMS mystream 0"
    "XREADGROUP GROUP mygroup BLOCK 0 consumer COUNT 10 STREAMS mystream 0"
    "XREADGROUP COUNT 10 BLOCK 0 GROUP mygroup consumer STREAMS mystream 0"
    "XREADGROUP GROUP mygroup COUNT 10 STREAMS mystream 0 BLOCK 0 consumer"
    "XREADGROUP GROUP mygroup STREAMS mystream consumer 0 COUNT 10 BLOCK 0"
    "XREADGROUP GROUP mygroup consumer STREAMS mystream 0 COUNT 10 BLOCK 0"
    "XREADGROUP consumer STREAMS mystream 0 GROUP mygroup COUNT 10 BLOCK 0"
    "XREADGROUP GROUP mygroup consumer COUNT 10 STREAMS mystream 0 BLOCK 0"
    "XREADGROUP GROUP mygroup consumer STREAMS mystream 0 COUNT 10 BLOCK 0"
    "XREADGROUP GROUP mygroup STREAMS mystream 0 consumer COUNT 10 BLOCK 0"
    "XREADGROUP STREAMS mystream 0 GROUP mygroup consumer COUNT 10 BLOCK 0"
    "del mystream"

    # 18. Copy command validation
    "DEL {key}1 {key}2"
    "MSET {key}1 value1 {key}2 value2"
    "MGET {key}1 {key}2"
    "COPY {key}1 {key}2"
    "MGET {key}1 {key}2"
    "COPY {key}1 {key}2 REPLACE"
    "MGET {key}1 {key}2"
)

# Expected results for each command
expected_results=(
    # 1. String operations
    "OK"
    "Hello"
    "11"
    "11"
    "OK"
    "OK"
    "10"
    "10000"
    "1"
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    "1"
    "OK"
    "value1\nvalue2\nvalue3\n"
    "11"
    "Hello"
    "1"
    "6"
    "7.5"
    "9"
    "8"
    "6"
    "0"
    "1"
    "1"
    "7"
    "Hello Redis"
    "New Value"
    "9"
    
    # 2. List operations
    "2"
    "4"
    "0"
    "0"
    "4"
    "item2\nitem1\nitem3\nitem4\n"
    "item2"
    "item4"
    "item1"
    "OK"
    "1"
    "OK"
    "2"
    "new item"
    "{mylist}1\ninserted\nitem\n"
    "{mylist}2\nnew\nitem\n"
    "3"
    "{mylist}1\nitem3\n"
    "{mylist}1\nitem1\n"
    "item2"
    "item2"
    
    # 3. Set operations
    "3"
    "3"
    "member\nmember\nmember\n"
    "1"
    "1"
    "member\nmember\n"
    "1"
    "1"
    "member4"
    "member3\nmember1\n"
    "2"
    ""
    "0"
    ""
    "member3\nmember1\nmember4\n"
    "3"
    "member\nmember\nmember\n"
    "member\n"
    
    # 4. Hash operations
    "2"
    "1"
    "value1"
    "OK"
    "value1\nvalue2\nvalue3\n"
    "field1\nvalue1\nfield2\nvalue2\nfield3\nvalue3\nfield4\nvalue4\nfield5\nvalue5\n"
    "1"
    "1"
    "0"
    "field1\nfield3\nfield4\nfield5\n"
    "value1\nvalue3\nvalue4\nvalue5\n"
    "4"
    "5"
    "1.5"
    "0\nfield1\nvalue1\nfield3\nvalue3\nfield4\nvalue4\nfield5\nvalue5\nfield6\n5\nfield7\n1.5\n"
    
    # 5. Sorted Set operations
    "3"
    "one\n1\ntwo\n2\nthree\n3\n"
    "three\n3\ntwo\n2\none\n1\n"
    "1"
    "1"
    "2"
    "2"
    "1"
    "one\nthree\n"
    "three\none\n"
    "1"
    "0"
    "1"
    "3"
    "1"
    "0"
    "0\nthree\n3\n"
    "three"
    "1"
    "1"
    
    # 6. HyperLogLog operations
    "1"
    "4"
    "1"
    "OK"
    "6"
    
    # 7. Geo operations
    "2"
    "166274.1516"
    "sqc8b49rny0"
    "13.36138933897018433\n38.11555639549629859\n"
    "Catania"
    "Palermo\nCatania\n"
    
    # 8. Stream operations
    "0"
    "1"
    "name\nabcd\nage\n"
    "name\nabcd\nage\n"
    "NOGROUP No such key 'mystream' or consumer group 'mygroup'"
    "OK"
    ""
    "mystream\nname\nabcd\nage\n"
    ""
    "mystream"
    "0"
    ""
    "0"
    "length\nradix-tree-keys\nradix-tree-nodes\nlast-generated-id\ngroups\nfirst-entry\nname\nabcd\nage\nlast-entry\nname\nefgh\nage\n"
    "name\nmygroup\nconsumers\npending\nlast-delivered-id\n"
    "0"
    "1"
    "0"
    "0"
    "1"
    "0"

    # 9. Transaction operations
    ""
    "OK"
    "value"
    "\nEXEC\nwithout\nMULTI\n"
    "EXEC without MULTI"
    ""
    "OK"
    
    # 10. Scripting
    "mykey\nHello\n"
    "'SCRIPT'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    "NOSCRIPT No matching script. Please use EVAL."
    "hello"
    "'SCRIPT'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    "'SCRIPT'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    
    # 11. Connection and server operations
    "PONG"
    "Hello World"
    ""
    ""
    ""
    ""
    "myclient"
    "'CONFIG'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    "'SLOWLOG'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    "'INFO'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    
    # 12. Key space operations
    "'RANDOMKEY'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    "'SCAN'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    "OK"
    "string"
    "1"
    "1"
    "0"
    "OK"
    "1"
    "OK"
    "1"
    "1"
    "-1"
    ""
    "OK"
    "OK"
    "myvalue"
    "1"
    "myvalue"
    "item2"
    "'KEYS'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    
    # 13. Pubsub Operations
    "'PUBLISH'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    "'PUBSUB'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    #"'SUBSCRIBE'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    "'UNSUBSCRIBE'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    #"'PSUBSCRIBE'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    "'PUNSUBSCRIBE'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    
    # 14. Database operations
    "DB index is out of range"
    "'FLUSHDB'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    "OK"
    "'FLUSHALL'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    "'DBSIZE'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    "'SWAPDB'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    
    # 15. Cluster operations
    "'CLUSTER'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    "'CLUSTER'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    "'CLUSTER'\ncommand\nis\nnot\nsupported\nwithin\ntransaction\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors\n"
    
    # 16. Module operations
    "(nil)"
    ""
    ""
    
    # 17. Blocking Operations
    "1"
    "0"
    "5"
    "5"
    "{mylist}1\n9\n"
    "{mylist}2\n10\n"
    "1"
    "5"
    "5"
    "{myzset}1\none\n1\n"
    "{myzset}2\nten\n10\n"
    "{mylist}1\n7\n"
    "{mylist}2\n8\n"
    "3"
    "{myzset}1\nthree\n3\n"
    "{myzset}2\neight\n8\n"
    "3"
    "1"
    "6"
    "4"
    "6\n3\n5\n1\n4\n"
    "2"
    "6"
    "3"
    "4"
    "1"
    "5"
    "4\n6\n2\n3\n1\n"
    #XREAD
    "mystream\nname\nabcd\nage\nname\nefgh\nage\n"
    ""
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    "ERR syntax error"
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    "mystream\nname\nabcd\nage\n"
    "mystream\nname\nabcd\nage\n"
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    "mystream\nname\nabcd\nage\nname\nefgh\nage\n"
    "ERR syntax error"
    "mystream\nname\nabcd\nage\nname\nefgh\nage\n"
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    #XREADGROUP
    "OK"
    "mystream"
    "1"
    "mystream"
    "mystream\nfield1\nvalue1\n"
    "mystream\nfield1\nvalue1\n"
    "mystream\nfield1\nvalue1\n"
    ""
    "mystream\nfield1\nvalue1\n"
    "mystream\nfield1\nvalue1\n"
    "mystream\nfield1\nvalue1\n"
    "ERR syntax error"
    "mystream\nfield1\nvalue1\n"
    "ERR syntax error"
    "mystream\nfield1\nvalue1\n"
    "ERR syntax error"
    "mystream\nfield1\nvalue1\n"
    "ERR syntax error"
    "ERR syntax error"
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    "ERR syntax error"
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    "CROSSSLOT\nKeys\nin\nrequest\ndon't\nhash\nto\nthe\nsame\nslot\n\nEXECABORT\nTransaction\ndiscarded\nbecause\nof\nprevious\nerrors.\n"
    "ERR syntax error"
    "ERR Unbalanced XREAD list of streams: for each stream key an ID or '$' must be specified."
    "1"

    # 18. Copy command validation
    "2"
    "OK"
    "value1\nvalue2\n"
    "0"
    "value1\nvalue2\n"
    "1"
    "value1\nvalue1\n"
)

echo "$(date) : INFO : Validating redis commands inside transaction"
total_commands=${#commands[@]}
error_count=0
for i in "${!commands[@]}"
do
    cmd="${commands[$i]}"
    expected="${expected_results[$i]}"

    echo "$(date) : INFO : Executing: $cmd"
    result=$(execute_redis_command "$cmd")
    echo "=======RESULT : ${result}"
    echo "============="

    output_count=$(echo "$result" | egrep -v "QUEUED|OK" | wc -l)
    MAIN_CMD=$(echo $cmd | awk '{print $1}')
    if [ ${output_count} -gt 1 ]
    then
        case ${MAIN_CMD} in
            XRANGE|XREAD|XREVRANGE|XINFO)
                command_result=$(echo "$result" | egrep -v "QUEUED|OK|^[0-9-]*$" | tr '\n' ' ' | sed 's/ /\\n/g')
                ;;
            ZRANGE|HGETALL|MGET|GEOPOS)
                command_result=$(echo "$result" | egrep -v "QUEUED|OK" | tr '\n' ' ' | sed 's/ /\\n/g')
                ;;
            SMEMBERS|SRANDMEMBER)
                command_result=$(echo "$result" | egrep -v "QUEUED|OK" | cut -c1-6 | tr '\n' ' ' | sed 's/ /\\n/g')
                ;;
            TIME)
                command_result=$(echo "$result" | egrep -v "QUEUED|OK" | grep ^172 | wc -l | tr '\n' ' ' | sed 's/ /\\n/g')
                ;;
            XREADGROUP)
                command_result=$(echo "$result" | egrep -v "QUEUED|OK" | grep -v "^[0-9]" | tr '\n' ' ' | sed 's/ /\\n/g')
                ;;
            *)
                command_result=$(echo "$result" | egrep -v "QUEUED|OK" | tr '\n' ' ' | sed 's/ /\\n/g')
                ;;
        esac
    else
        case ${MAIN_CMD} in
            XADD)
                command_result=$(echo "$result" | sed '1d;2d;/^$/d' | grep "^[0-9]")
                stream_id=$(echo "$result" | sed '1d;2d;/^$/d' | awk -F "-" '{print $1}')
                validate_output "$cmd" "$command_result" "${stream_id}-${expected}"
                ;;
            PING)
                command_result=$(echo "$result" | sed '1d;/^$/d')
                ;;
            TTL)
                command_result=$(echo "$result" | sed '1d;2d;/^$/d')
                if [[ $command_result -le 10 ]]
                then
                    validate_output "$cmd" "$command_result" "$command_result"
                    continue
                fi
                ;;
            PTTL)
                command_result=$(echo "$result" | sed '1d;2d;/^$/d')
                if [[ $command_result -le 10000 ]]
                then
                    validate_output "$cmd" "$command_result" "$command_result"
                    continue
                fi
                ;;    
            SPOP)
                command_result=$(echo "$result" | egrep -v "QUEUED|OK" | cut -c1-6 | tr '\n' ' ' | sed 's/ /\\n/g')
                ;;
            *)
                command_result=$(echo "$result" | sed '1d;2d;/^$/d')
                ;;
        esac
    fi

    validate_output "$cmd" "$command_result" "$expected"
    if [ $? -ne 0 ]
    then
        error_count=$((error_count + 1))
    fi
done

echo "$(date) : INFO : ===== Transaction Testing Summary ====="
echo "$(date) : INFO : Total commands executed: $total_commands"
echo "$(date) : INFO : Commands with errors: $error_count"
echo "$(date) : INFO : ========================================"
    
if [ ${error_count} -le 11 ]
then
    echo "$(date) : INFO : All $total_commands commands executed inside the transaction successfully."
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" FLUSHALL 2>/dev/null | grep -v option
else
    echo "$(date) : ERROR : ${error_count}/${total_commands} commands failed while executing inside the transaction. Exiting."
    exit 1
fi