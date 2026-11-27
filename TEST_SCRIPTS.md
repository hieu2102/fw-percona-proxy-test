# Test scripts reference

This page describes every script in the repository: what it tests, how to run it, and how it reports pass/fail. For setup and an overview, see the [README](README.md).

| Script | Type | Summary |
| --- | --- | --- |
| [`commands_sanity.sh`](#commands_sanitysh) | Functional | General Valkey command checks, including blocking operations, scripting, streams, and cluster commands |
| [`commands_sanity_valkey8.sh`](#commands_sanity_valkey8sh) | Functional | Standalone checks for Valkey 8 features and error replies |
| [`pubsub_commands.sh`](#pubsub_commandssh) | Functional | Publish counts, channel and pattern subscriptions, and PUBSUB introspection |
| [`pubsub_commands_valkey8.sh`](#pubsub_commands_valkey8sh) | Functional | CSV-driven pub/sub and client-command cases |
| [`transaction_commands.sh`](#transaction_commandssh) / [`transaction_commands_valkey8.sh`](#transaction_commands_valkey8sh) | Functional | Commands wrapped in MULTI/EXEC |
| [`negative_testing_commands_valkey8.sh`](#negative_testing_commands_valkey8sh) | Negative | Authentication, wrong-type operations, and malformed commands |
| [`valgrind-memory-leak-scripts/*`](#valgrind-memory-leak-scripts) | Memory | Workloads against Envoy running under Valgrind |
| [`address-sanitiser-scripts/*`](#address-sanitiser-scripts) | Memory | Workloads against an ASan-instrumented Envoy build |
| [`k8s/deploy-valkey-cluster.sh`](#deploy-a-valkey-cluster-on-kubernetes) | Setup | Installs the Valkey Operator and deploys the benchmark cluster |
| [`endurance-test-scripts/*`](#endurance-test-scripts) | Endurance | Long-running benchmark, pub/sub churn, streams and periodic client kills |

## `commands_sanity/`

All seven scripts invoke `valkey-cli` from the local shell. Install Bash and `valkey-cli`, then use the connection variables listed below. Environment variables replace the former Kubernetes config file. The two command sanity scripts use `PROXY_*` variables. The pub/sub, transaction, and negative scripts use `VALKEY_*` variables. Run the examples from the repository root.

**Use a disposable test endpoint.** The general, Valkey 8 feature, transaction, and negative scripts issue `FLUSHALL`. Some pub/sub and feature checks also terminate client connections.

### `commands_sanity.sh`

This suite connects with `valkey-cli -c --raw`. `PROXY_HOST` defaults to `localhost` and `PROXY_PORT` to `7777`. The cluster cases expect a cluster-aware endpoint. Install a `timeout` that supports `--kill-after`, such as GNU coreutils `timeout`.

```bash
PROXY_HOST=localhost PROXY_PORT=7777 ./commands_sanity/commands_sanity.sh
```

| Case | Coverage |
| --- | --- |
| 01–02 | Set and sorted-set operations, including union, intersection, and difference. |
| 03 | List and sorted-set pops, `BRPOPLPUSH`, `BLMOVE`, `SORT`, and `LPOS`. Empty-list `BLPOP` and `BRPOP` checks look for a blank raw reply after the server timeout. Six blocking commands with a server timeout of `0` must keep waiting until the local 10-second timeout stops the client. |
| 04 | `SELECT 0`, missing arguments to `CLIENT SETNAME`, and `SCRIPT LOAD`, `EVALSHA`, `SCRIPT EXISTS`, and `SCRIPT FLUSH SYNC`. |
| 05 | `CLUSTER KEYSLOT` expects slot 6918 for both `{test}1` and `{test}2`. `CLUSTER SLOTS` is parsed from CSV output and the slot ranges must total 16384. |
| 06–09 | String operations, streams and consumer groups, `PING`/`TIME`/`QUIT`/`EXIT`, and hashes. The blocking stream test attempts both a short read and a read that waits for the local timeout. |
| 11 | `FLUSHALL`, `GETEX` expiration, `GETDEL`, `MSETNX`, `EXISTS`, `DEL`, `COPY`, and `SCAN`. Positive `SCAN` checks require at least one matching key. Invalid cursor values must return `ERR invalid cursor`. |

Run the full suite in order because some groups reuse data created earlier. The bitwise group, SLOWLOG checks, and INFO/CONFIG checks are disabled in the script.

The script prints timestamped `INFO`, `PASSED`, `FAILED`, `ERROR`, and `DEBUG` messages. `EXIT_ON_ERROR` is set to `0` in the script, so inspect the log for failures even when the run reaches the elapsed-time line. The BLPOP/BRPOP timeout checks use `./test_block_cmd.log` and delete it when the check passes.

### `commands_sanity_valkey8.sh`

This standalone suite runs the Valkey 8 feature and error checks. The host is fixed to `localhost`, and `PROXY_PORT` defaults to `7777`. Point it at an endpoint that supports the commands and options below.

```bash
PROXY_PORT=7777 ./commands_sanity/commands_sanity_valkey8.sh
```

- `SET ... IFEQ` tests a matching and nonmatching update, then verifies that the stored value is still `v2`.
- Nested `MULTI` and `WATCH` inside `MULTI` each use one local CLI session. The checks look for `MULTI calls can not be nested` and `ERR WATCH inside MULTI is not allowed`, respectively.
- `SCAN 0 TYPE faketype` expects `ERR unknown type name`. The `BITPOS` and `BITCOUNT` cases check invalid arguments on nonexistent keys.
- Server and client checks cover `BGSAVE CANCEL`, `CLIENT KILL MAXAGE 3600`, and the `CLIENT LIST` filters `SKIPME YES` and `MAXAGE 60`. `CLIENT KILL` can disconnect other clients.

The script flushes at startup and again after the checks complete. The invalid `SCAN` type, `BGSAVE CANCEL`, and `CLIENT KILL` checks can log failures and continue. Other failed checks can exit with code 1. A full run prints elapsed time.

### `pubsub_commands.sh`

`VALKEY_HOST` defaults to `localhost` and `VALKEY_PORT` to `7777`. The script adds the `-a` option when `VALKEY_PASSWORD` is nonempty. It requires `timeout`.

```bash
VALKEY_HOST=localhost VALKEY_PORT=7777 ./commands_sanity/pubsub_commands.sh
```

- Publishes `Hello` to `test_channel_100` and expects counts of `0` without a subscriber and `1` with a subscriber. It checks `PUBSUB NUMSUB`, `NUMPAT`, and `CHANNELS`.
- Checks the acknowledgments for `SUBSCRIBE` and `PSUBSCRIBE` using five-second invocations and raw output with literal `\n` separators. Background subscribers used for publish and channel-list checks have a 15-second timeout.
- The check labelled `PUNSUBSCRIBE` currently repeats `UNSUBSCRIBE test_channel_100`.
- Cleanup checks `CLIENT LIST` for `cmd=subscribe`. If it finds an active subscriber, it can kill local processes whose command lines match `subscribe` and `VALKEY_HOST`, including processes started outside the script.

The script prints expected and actual values on failures. Use the `FAILED` lines to determine which checks failed.

### `pubsub_commands_valkey8.sh`

This runner uses the same connection variables as `pubsub_commands.sh` and requires `timeout` and `stdbuf` for timed subscriptions. It reads [`pubsub_commands_valkey8.csv`](commands_sanity/data/pubsub_commands_valkey8.csv) relative to the script.

```bash
VALKEY_HOST=localhost VALKEY_PORT=7777 ./commands_sanity/pubsub_commands_valkey8.sh
```

Each pipe-delimited row contains `command | expected reply | check exit status | ignore`. A third column of `1` checks the CLI exit status. Other values compare the raw reply with the expected text, using literal `\n` separators. A fourth column of `1` skips the row. Lines beginning with `#` are ignored.

The shipped rows cover `UNSUBSCRIBE`, `PUNSUBSCRIBE`, `CLIENT LIST` filters, `CLIENT KILL MAXAGE 3600`, `PUBSUB NUMSUB` and `NUMPAT`, `PUBLISH` with no subscribers, and the `SUBSCRIBE` acknowledgment. The runner bounds the uppercase `SUBSCRIBE` row with a five-second `timeout` and uses `stdbuf` to line-buffer the reply. Review the per-row `PASSED` or `FAILED` messages. Failures are logged without an aggregate failure exit status.

### `transaction_commands.sh`

The runner loads [`transaction_commands.csv`](commands_sanity/data/transaction_commands.csv) and sends each enabled command in a separate `MULTI` / command / `EXEC` session. Each pipe-delimited row contains the command, expected result, and optional ignore flag. Cases run in file order and can depend on keys created earlier. The expected replies include cluster errors and proxy-specific transaction rejections.

Set `VALKEY_HOST` explicitly. `VALKEY_PORT` defaults to `6379`. Set `VALKEY_PASSWORD` for an authenticated endpoint. Use a Bash version with `readarray`.

```bash
VALKEY_HOST=localhost VALKEY_PORT=7777 ./commands_sanity/transaction_commands.sh
```

The runner issues `FLUSHALL` and loads a small SET/GET Lua script before the sweep. It normalizes replies before comparing them with the fixture, including flattening multiline output into literal `\n` separators and applying command-specific handling for replies such as stream IDs and TTLs.

**Command coverage**

- Strings: SET, GET, APPEND, STRLEN, SETEX, PSETEX, TTL, PTTL, SETNX, MSETNX (a cross-slot case that expects `CROSSSLOT` + `EXECABORT`, and a hash-tagged case), MSET, MGET, SETRANGE, GETRANGE, INCR, INCRBY, INCRBYFLOAT, DECR, DECRBY, SETBIT, GETBIT, BITCOUNT, BITPOS, GETSET.
- Lists: LPUSH, RPUSH, LPUSHX, RPUSHX, LLEN, LRANGE, LPOP, RPOP, LINDEX, LSET, LREM, LTRIM, LINSERT, RPOPLPUSH, BLPOP, BRPOP (timeouts 1 and 0), BRPOPLPUSH (timeouts 0 and 1).
- Sets: SADD, SCARD, SMEMBERS, SISMEMBER, SREM, SRANDMEMBER, SMOVE, SDIFF, SDIFFSTORE, SINTER, SINTERSTORE, SUNION, SUNIONSTORE, SPOP.
- Hashes: HSET, HSETNX, HGET, HMSET, HMGET, HGETALL, HDEL, HEXISTS, HKEYS, HVALS, HLEN, HINCRBY, HINCRBYFLOAT, HSCAN.
- Sorted sets: ZADD, ZRANGE … WITHSCORES, ZREVRANGE, ZRANK, ZREVRANK, ZCOUNT, ZINCRBY, ZREM, ZRANGEBYSCORE, ZREVRANGEBYSCORE, ZREMRANGEBYRANK, ZREMRANGEBYSCORE, ZCARD, ZSCORE, ZUNIONSTORE, ZINTERSTORE, ZSCAN, ZRANGEBYLEX, ZLEXCOUNT, ZREMRANGEBYLEX.
- HyperLogLog: PFADD, PFCOUNT, PFMERGE.
- Geo: GEOADD, GEODIST, GEOHASH, GEOPOS, GEORADIUS, GEORADIUSBYMEMBER.
- Streams: XADD (auto and explicit IDs), XLEN, XRANGE, XREVRANGE, XPENDING (before and after the group exists), XGROUP CREATE/DESTROY, XREAD, XREADGROUP, XACK, XINFO STREAM/GROUPS, XTRIM, XDEL.
- Transaction commands nested inside the wrapper: MULTI, SET, GET, EXEC, DISCARD, WATCH, UNWATCH.
- Scripting: EVAL; EVALSHA with an unknown SHA (expects `NOSCRIPT`) and with the SHA of the script loaded at startup (expects `hello`); SCRIPT LOAD/EXISTS/FLUSH (expected to be rejected inside a transaction).
- Connection/server: PING, ECHO, TIME, CLIENT LIST/GETNAME/SETNAME. CONFIG GET, SLOWLOG GET and INFO are expected to be rejected inside a transaction.
- Keyspace: TYPE, EXISTS, DEL, UNLINK, EXPIRE, PERSIST, TTL, MOVE, RENAME, RENAMENX, SORT … ALPHA. RANDOMKEY, SCAN and KEYS are expected to be rejected inside a transaction.
- Pub/sub: PUBLISH, PUBSUB CHANNELS, UNSUBSCRIBE and PUNSUBSCRIBE are all expected to be rejected inside a transaction. SUBSCRIBE and PSUBSCRIBE are commented out.
- Database: SELECT 1 (expects `DB index is out of range`), SELECT 0 (expects `OK`). FLUSHDB, FLUSHALL, DBSIZE and SWAPDB are expected to be rejected inside a transaction.
- Cluster/modules: CLUSTER INFO/NODES/SLOTS (expected to be rejected), MODULE LIST (expects `(nil)`), MODULE LOAD/UNLOAD (expect an empty result).
- Blocking commands: BLPOP, BRPOP, BRPOPLPUSH, BZPOPMIN, BZPOPMAX and BLMOVE (all four LEFT/RIGHT combinations), with non-zero and zero timeouts, checked with LRANGE.
- XREAD/XREADGROUP argument permutations: 19 XREAD and 23 XREADGROUP orderings of `BLOCK`/`COUNT`/`STREAMS`/`GROUP`/consumer (the XREAD cases include `COUNT 0` and `COUNT -1`). Depending on the ordering, the expected result is a valid read, an empty result, `ERR syntax error`, `CROSSSLOT` + `EXECABORT`, or the "Unbalanced XREAD list of streams" error.
- COPY: `COPY {key}1 {key}2` without `REPLACE` (expects `0`) and with `REPLACE` (expects `1`), verified with MGET.

**Reading the results**

- Matching cases are quiet. A reply containing `WRONGTYPE`, `NOSCRIPT`, `NOTBUF`, or `SYNTAXERR` is logged as `FATAL` and counted as an error. This also applies when the fixture itself expects `NOSCRIPT`.
- An ordinary reply mismatch logs `FAILED` and triggers a bare `exit` in the validator. That can end the run before the summary with status 0.
- If the runner reaches its summary, it reports total fixture rows, errors, and skipped rows. At most 11 counted errors take the final `FLUSHALL` path. More than 11 exits with code 1.

### `transaction_commands_valkey8.sh`

This entry point checks that [`transaction_commands_valkey8_prechecks.csv`](commands_sanity/data/transaction_commands_valkey8_prechecks.csv) is readable, then sources `transaction_commands.sh`. It uses the same connection settings, prerequisites, and reporting.

```bash
VALKEY_HOST=localhost VALKEY_PORT=7777 ./commands_sanity/transaction_commands_valkey8.sh
```

The wrapper defines a helper for the precheck file and sets a path to [`transaction_commands_valkey8.csv`](commands_sanity/data/transaction_commands_valkey8.csv). In the current code the shared runner reads `transaction_commands.csv` directly, and the wrapper's normal entry point leaves the precheck helper uncalled.

### `negative_testing_commands_valkey8.sh`

This is the negative suite in `commands_sanity/`. It uses `VALKEY_HOST` and `VALKEY_PORT`, which default to `localhost` and `7777`. For the authentication cases, set `VALKEY_PASSWORD` in your shell to the password for the test endpoint.

```bash
VALKEY_HOST=localhost VALKEY_PORT=7777 ./commands_sanity/negative_testing_commands_valkey8.sh
```

- **Case 01** checks authentication and runs wrong-type operations and malformed commands across strings, lists, sets, hashes, sorted sets, HyperLogLog, geospatial data, pub/sub, transactions, scripting, keys, and streams. It also checks invalid `SCAN` types and cursors and invalid `BITCOUNT`/`BITPOS` arguments. The transaction cases send nested `MULTI` and `WATCH` inside `MULTI` in separate CLI sessions.
- **Case 02** sends a command list with no arguments. It runs a `PING` check before each command and retries every five seconds when the CLI reports a failure. Replies matching `invalid request`, `wrong number of arguments`, `ERR`, or `syntax error` pass. Commands such as `PING`, `FLUSHALL`, `FLUSHDB`, and `DBSIZE` are sent before they are reported as `SKIPPED`.

Case 01 prints a counted summary and exits with code 1 above five counted failures. Authentication messages are logged separately from those counters. Case 02 exits with code 1 above six failures. If both sections stay within their thresholds, the final exit status comes from checking the final `FLUSHALL SYNC` reply for `OK`.

Some expectations depend on endpoint policy and reply wording. For example, the pub/sub case expects `NOPERM` and `SELECT 99` expects a cluster-mode error. Cases with an empty expected substring accept any reply.

---

## valgrind-memory-leak-scripts/

All three scripts check the proxy for memory leaks the same way. For each test group they start Envoy under `valgrind --leak-check=full --show-leak-kinds=all`, wait until the proxy answers `PING`, and send a fixed set of Redis commands through it. They then stop Envoy with SIGTERM, wait 10 s, and pull the valgrind `LEAK SUMMARY` from that group's log.

**Prerequisites shared by all three** (every value is hard-coded; there are no env vars or CLI args):

- Linux with `valgrind` and `redis-cli` on `PATH`.
- An Envoy binary at `./bazel-bin/source/exe/envoy-static`. In practice this means running from the root of an Envoy source tree after a Bazel build.
- An Envoy config named `envoy.yaml` in the current directory, with a `redis_proxy` listener on `127.0.0.1:1999` in front of your Redis/Valkey cluster. **This file is not included**, so you have to write it yourself.
- Python scripts: Python 3.6+ with the standard library only (no pip packages).

---

### `non_blocking_commands.py`

**Purpose**: Runs a wide range of mostly non-transactional Redis commands through the proxy, one group at a time. Each of its 69 groups (66 unique names) gets a fresh valgrind-wrapped Envoy, and the script records the valgrind leak summary for each group.

**What it tests** (each command is sent once, with `redis-cli -p 1999 <command>`):

- **Streams**: XADD (MAXLEN ~, NOMKSTREAM, MINID ~, LIMIT), XRANGE (COUNT), XREVRANGE (COUNT), XLEN, XDEL (single and multiple IDs), XTRIM (MAXLEN, MAXLEN ~, MINID, MINID ~ LIMIT), XGROUP (CREATE, CREATECONSUMER, SETID, DESTROY, DELCONSUMER, CREATE ... MKSTREAM, SETID ... ENTRIESREAD), XREADGROUP (COUNT, BLOCK 5000, NOACK, multi-stream, explicit ID), XPENDING (summary, range, per-consumer, IDLE), XCLAIM (JUSTID, FORCE, IDLE, TIME, RETRYCOUNT), XAUTOCLAIM (COUNT, JUSTID), XINFO (STREAM, STREAM FULL, GROUPS, CONSUMERS)
- **Sets**: SADD, SMEMBERS, SREM, SMISMEMBER, SUNION, SDIFF, SINTER, SUNIONSTORE, SDIFFSTORE, SINTERSTORE
- **Sorted sets**: ZUNIONSTORE / ZINTERSTORE (WEIGHTS, AGGREGATE MIN/MAX), ZRANGESTORE (BYSCORE, REV, LIMIT), ZUNION (WEIGHTS, AGGREGATE MAX), ZINTER (WITHSCORES, WEIGHTS, AGGREGATE), ZDIFF (WITHSCORES), ZDIFFSTORE, ZMSCORE, ZRANDMEMBER (count, negative count, WITHSCORES)
- **Blocking lists / zsets**: BRPOPLPUSH, BZPOPMAX, BZPOPMIN, BLPOP, BRPOP (timeout 0 and 5), BLMOVE (LEFT/RIGHT, timeout 0 and 5). Setup uses LPUSH, RPUSH and ZADD (see caveats).
- **Lists**: LPOS (RANK, COUNT, MAXLEN)
- **Hashes**: HRANDFIELD (count, negative count, WITHVALUES)
- **Strings / keys**: GETDEL, GETEX (EX, PX, EXAT, PXAT, PERSIST), MSETNX, SUBSTR, RENAME, RENAMENX, RANDOMKEY, KEYS, SCAN (MATCH, TYPE, COUNT), SORT (DESC, ALPHA, LIMIT, BY, GET, STORE), BITOP (AND, OR, XOR, NOT)
- **HyperLogLog**: PFMERGE
- **Geo**: GEORADIUS, GEORADIUSBYMEMBER (WITHDIST, WITHCOORD, WITHHASH, COUNT, ASC/DESC, STORE), GEOSEARCH, GEOSEARCHSTORE (FROMMEMBER, FROMLONLAT, BYBOX, BYRADIUS, STOREDIST)
- **Pub/Sub introspection**: PUBSUB CHANNELS (with and without a pattern), PUBSUB NUMSUB, PUBSUB NUMPAT
- **Scripting**: SCRIPT LOAD, EXISTS, FLUSH, KILL
- **Server / connection / admin**: FLUSHALL (sync and ASYNC), SLOWLOG (GET, GET 10, LEN, RESET), CONFIG (GET \*, GET maxmemory, SET maxmemory 2GB, RESETSTAT), CLIENT (LIST, GETNAME, SETNAME, KILL, PAUSE 5000), INFO (all, memory), CLUSTER (INFO, NODES, SLOTS, KEYSLOT), SELECT 0/1, HELLO (2, 3 AUTH, 3 SETNAME), UNWATCH

**How it runs**:

- Connects with `redis-cli -p 1999` (default host 127.0.0.1, no `-c` cluster mode). Commands go through a shell (`shell=True`), so shell quoting, globbing and redirection apply (see caveats).
- For each group it runs:
  `valgrind --leak-check=full --show-leak-kinds=all --log-file=envoy_valgrind_<group>_xmem_read.log ./bazel-bin/source/exe/envoy-static -c envoy.yaml --log-level debug`
  Envoy's stdout and stderr go to `build_output_xread.log`, which is overwritten for each group.
- It waits up to 600 s for the valgrind/Envoy process to appear and up to 600 s for `PING` to return `PONG`. After the commands it sends SIGTERM, waits up to 900 s for the process to exit, then sleeps 10 s before reading the log.
- Each command has a 10 s timeout. Commands whose text contains `block` (case-insensitive) get 7 s, which in practice means only the `XREADGROUP ... BLOCK 5000` call. BLPOP, BRPOP, BZPOP\*, BRPOPLPUSH and BLMOVE don't contain that word, so they keep 10 s. A command that times out is killed and recorded as `Command timed out`. For example, `blmove source destination left right 0` always runs into this.
- Example: `cd <envoy-src-root> && sudo python3 /path/to/non_blocking_commands.py` (it must run as root; see caveats).

**Pass/fail & output**:

- It gives no pass/fail verdict, and the exit code does not reflect leaks.
- `memory_leak_report.txt` lists, for each group, every command with its stdout (or `Success` if stdout was empty) or, if anything was written to stderr, that stderr as the error.
- It also includes the group's leak summary: the `LEAK SUMMARY:` line plus the next 3 lines (definitely, indirectly and possibly lost), taken from the last 15 lines of the valgrind log. If the summary isn't found there, it records `LEAK SUMMARY not found`. That is also what you get when valgrind finds no leaks at all, because valgrind then prints no `LEAK SUMMARY`.
- You have to read the report yourself to judge whether there are leaks.

**Notes / caveats**:

- **You must run it as root.** The code finds the Envoy PID with the regex `\s*root\s+(\d+)\s+.*valgrind.*envoy-static` against `ps -ef | grep valgrind | grep envoy-static` output. If you run it as any other user, it waits the full 600 s and then reports a timeout.
- **The "Envoy started" check can pass too early.** When run as root, the regex can also match the script's own `sh -c "ps -ef | grep valgrind | grep envoy-static"` helper process, because that line contains both words. The `PING` wait is what really waits for startup.
- **Shell globbing and redirection change some commands.** Commands are not quoted for the shell:
  - The bare `*` in the XADD calls, `keys *` and `config get *` expands to the file names in the current directory, which in an Envoy source tree is a long list.
  - In `sort user_ids BY user:*->age` and `sort user_ids GET user:*->name`, the shell treats `>` as a redirect. The command is cut short and its output is written to files named `age` and `name` in the current directory. The report then shows `Success`.
- **Missing commas in five groups.** In `brpoplpush`, `bzpopmax`, `bzpopmin`, `blpop` and `brpop`, the setup lines have no commas between them. Python joins adjacent strings, so the setup commands and the first blocking command are sent as one malformed command. For example, `lpush pending_tasks "task1"lpush notification_queue ...brpoplpush pending_tasks active_tasks 0` becomes a single LPUSH. The intended setup and that first (timeout 0) blocking call never run as separate commands.
- **`iterations = 5` does nothing.** It is passed to `run_test_group` but never used, so each command runs once.
- **Duplicate group names.** `sunionstore`, `smismember` and `xclaim` each appear twice. The later group reuses the same valgrind log file name and overwrites the earlier one.
- **Report crash after a startup failure.** If Envoy fails to start, `PING` times out, or shutdown times out, the group's result has no `results` key. Writing the report then fails with a `KeyError`.
- **Destructive commands.** `FLUSHALL`, `CONFIG SET maxmemory 2GB`, `CONFIG RESETSTAT`, `SLOWLOG RESET`, `SCRIPT FLUSH` and `CLIENT PAUSE 5000` change the backend if the proxy forwards them. Use a disposable cluster.
- **Many commands are expected to fail.** Lots of them do one of the following:
  - target keys or groups that don't exist;
  - use placeholder IDs (`ID1 ID2 ID3`);
  - use invalid syntax, such as `"> >"` as one ID argument or `fromlon/fromlat` in GEOSEARCH\*;
  - use placeholder credentials (`HELLO 3 AUTH admin StrongPassword123`).

  Error replies are expected and are never checked. The test only cares whether the proxy leaks while handling them.

---

### `blocking_commands.sh`

**Purpose**: Bash script that checks for leaks when the proxy handles Pub/Sub and blocking stream reads (plus a few basic commands). It runs four groups, each against a fresh valgrind-wrapped Envoy.

**What it tests**:

- **pubsub**:
  - Starts two background subscribers, `PSUBSCRIBE test_*` and `SUBSCRIBE test_channel`, each killed by `timeout 5s`.
  - Then sends `PUBSUB CHANNELS`, 5 × `PUBLISH test_channel "Message N"`, `PUBSUB NUMSUB test_channel`, `PUBSUB NUMPAT`, `PUBSUB CHANNELS`, `PUNSUBSCRIBE test_*`, `UNSUBSCRIBE test_channel`, and `PUBSUB CHANNELS` again.
- **xread**: XADD ×2 (the second XADD's output is captured as the ID), `XREAD COUNT 2 STREAMS mystream 0-0`, and `XREAD BLOCK 5000 COUNT 1 STREAMS mystream <id>` (wrapped in `timeout 5s`).
- **xreadgroup**:
  - Setup: XADD plus `XGROUP CREATE ... 0-0 MKSTREAM` on `order_stream`, `notification_stream`, `sensor_data`, `event_log1`, `event_log2` and `audit_log`.
  - Then XREADGROUP with COUNT, BLOCK 5000 (wrapped in `timeout 5s`), NOACK, two streams (`event_log1 event_log2 ">" ">"`), and explicit ID `0-0`.
- **other**: SET, GET, HSET, HGET.

**How it runs**:

- Settings are variables at the top of the script and can only be changed by editing it:

  | Variable | Default |
  | --- | --- |
  | `ENVOY_BINARY` | `./bazel-bin/source/exe/envoy-static` |
  | `ENVOY_CONFIG` | `envoy.yaml` |
  | `REDIS_PORT` | `1999` |
  | `MEMORY_LEAK_REPORT` | `memory_leak_report_blocking_commands.txt` |
  | `CHANNEL` | `test_channel` |
  | `PATTERN` | `test_*` |

- Connects with `redis-cli -c -h 127.0.0.1 -p $REDIS_PORT` (cluster mode on).
- Each normal command is retried up to 3 times, 1 s apart, if `redis-cli` exits non-zero.
- For each group, the valgrind log goes to `envoy_valgrind_<group>_test.log` and Envoy's output goes to `build_output_<group>.log`.
- Startup and shutdown timeouts match the Python scripts: 600 s for start, 600 s for `PING`, 900 s for exit, then a 10 s sleep before the log is parsed. The Envoy process is found with `pgrep -f "valgrind.*envoy-static"`, so root is not required.
- Also needs `timeout` from coreutils, plus `pgrep` and `awk`.
- Example: `cd <envoy-src-root> && bash /path/to/blocking_commands.sh`. The file is not executable, so you have to call it with `bash`.

**Pass/fail & output**:

- It gives no pass/fail verdict. Command output and progress are printed to stdout.
- After each group it appends `Running test group: <group>` and the valgrind block from `LEAK SUMMARY:` through `suppressed:` to `memory_leak_report_blocking_commands.txt`. If valgrind found no leaks at all, it prints no `LEAK SUMMARY`, so only the header line is appended.
- The exit status is that of the final `run_test_group "other"` call. That is normally 0 (from the last `echo`), so it does not reflect leaks. A `return 1` from the earlier `run_test_group` calls is never checked.

**Notes / caveats**:

- **The report file only grows.** It is appended to and never truncated, so results from earlier runs pile up.
- **`REDIS_CLUSTER_NODES` is unused.** It is defined but never referenced. `LOG_FILE` is also overwritten for each group.
- **Unquoted `*` in XADD.** In `XADD mystream * ...` and the other XADD calls, the shell expands `*` to the file names in the current directory, which in an Envoy source tree is a long list. Quote it (`'*'`) if you want auto-generated IDs.
- **Retry messages can corrupt the captured ID.** `execute_redis_command` prints its "Command failed, retrying..." message to stdout, and the stream ID is captured from that same stdout. `$stream_id` is also unquoted in the XREAD BLOCK call.
- **Pub/Sub timing is tight.**
  - Each background subscriber lives 5 s, and the script sleeps 2 s + 2 s + 2 s before publishing. The pattern subscriber will normally have exited before any message is published.
  - `PUNSUBSCRIBE` and `UNSUBSCRIBE` are sent on new connections, not on the subscriber connections.
- **Possible cross-slot errors.** The two-stream XREADGROUP (`event_log1`, `event_log2`) uses keys without hash tags, which may land in different cluster slots.
- **Unknown group name leaks an Envoy process.** For a group name it doesn't recognise, `run_test_group` returns without stopping Envoy. This can't happen with the four hard-coded groups.

---

### `mem_leak_transaction.py`

**Purpose**: Checks the proxy for leaks while it handles `MULTI`/`EXEC` transactions. Each of 13 command groups is wrapped in one transaction and sent 100 times against a fresh valgrind-wrapped Envoy. At the end the script gives a simple pass/fail verdict.

**What it tests** (each group is sent as `MULTI` + commands + `EXEC`; most multi-key groups use hash tags such as `{key}`, `{mylist}` or `{myset}` so the keys share a slot):

- **Strings**: SET, GET, APPEND, STRLEN, TTL, PTTL, SETRANGE, GETRANGE, INCR, INCRBY, INCRBYFLOAT, DECR, DECRBY, SETBIT, GETBIT, BITCOUNT, BITPOS
- **Lists**: LPUSH, RPUSH, LPUSHX, RPUSHX, LLEN, LRANGE, LPOP, RPOP, LINDEX, LREM, LTRIM, SORT ALPHA, RPOPLPUSH
- **Sets**: SADD, SCARD, SMEMBERS, SISMEMBER, SREM, SRANDMEMBER, SPOP, SMOVE, SDIFF, SDIFFSTORE, SINTER, SINTERSTORE, SUNION, SUNIONSTORE
- **Hashes**: HSET, HSETNX, HGET, HMSET, HMGET, HGETALL, HDEL, HEXISTS, HKEYS, HVALS, HLEN, HINCRBY, HINCRBYFLOAT, HSCAN
- **Sorted sets**: ZADD, ZRANGE / ZREVRANGE WITHSCORES, ZRANK, ZREVRANK, ZCOUNT, ZINCRBY, ZREM, ZRANGEBYSCORE, ZREVRANGEBYSCORE, ZREMRANGEBYRANK, ZREMRANGEBYSCORE, ZCARD, ZSCORE, ZUNIONSTORE, ZINTERSTORE, ZSCAN, ZRANGEBYLEX, ZLEXCOUNT, ZREMRANGEBYLEX
- **HyperLogLog**: PFADD, PFCOUNT, PFMERGE
- **Geo**: GEOADD, GEODIST, GEOHASH, GEOPOS, GEORADIUS, GEORADIUSBYMEMBER
- **Streams**: XADD (auto and explicit ID), XLEN, XRANGE, XREVRANGE, XPENDING (before group creation, after it, and after XACK), XGROUP CREATE/DESTROY (DESTROY twice), XREAD, XREADGROUP (`>` and `0`), XACK, XINFO STREAM/GROUPS, XTRIM, XDEL (twice)
- **Server**: PING, ECHO, TIME, CLIENT LIST/SETNAME/GETNAME
- **Keyspace**: TYPE, EXISTS, DEL, UNLINK, EXPIRE, PERSIST, TTL, RENAME
- **Copy**: DEL, MSET, MGET, COPY, COPY ... REPLACE
- **Blocking commands inside MULTI**:
  - Setup: DEL, LPUSH, RPUSH, ZADD.
  - Pops: BLPOP, BRPOP, BRPOPLPUSH, BZPOPMIN, BZPOPMAX, with finite and 0 timeouts, plus wrong-type BLPOP/BRPOP calls on zset keys.
  - Moves: BLMOVE in all four LEFT/RIGHT combinations, with timeout 1000 and 0, plus LRANGE.
- **XREAD / XREADGROUP with BLOCK inside MULTI**:
  - Setup: DEL, then XREADGROUP before the group exists, XGROUP CREATE (twice), and XADD.
  - XREAD with BLOCK 100/0, COUNT 1/-1 and ID `0`.
  - XREADGROUP with COUNT 10, BLOCK 10000/0 and IDs `0` and `>`.

**How it runs**:

- Each transaction is sent as `echo '<MULTI\n...\nEXEC>' | redis-cli -p 1999` (no `-c`), with a 15 s timeout per transaction.
- `iterations = 100` transactions per group. The Envoy command line and startup/shutdown handling match `non_blocking_commands.py`. The valgrind log is `envoy_valgrind_<group>_xmem_read.log`, and Envoy's output goes to `build_output.log`, which is overwritten for each group.
- Example: `cd <envoy-src-root> && sudo python3 /path/to/mem_leak_transaction.py`. There is no shebang, so always call it with `python3`.

**Pass/fail & output**:

- `memory_leak_report_for_transaction.txt` contains, for each group and iteration:
  - the commands with their output lines;
  - a `Transaction Result:` line (the last output line);
  - the group's leak summary (the same 4-line extract as `non_blocking_commands.py`).
- If `redis-cli` writes anything to stderr, or the transaction times out, that iteration is recorded as a single error entry.
- After writing the report, the script greps it for every `definitely lost:` line and prints `Memory Leak Analysis Result:` with one of:
  - `Passed: No memory leaks detected.` if every line contains `0 bytes in 0 blocks`.
  - `Failed: Memory leak is identified...` otherwise.
  - `Failed: No 'definitely lost' information found...` if no such line exists.
- Indirectly and possibly lost bytes are not considered. The exit code is 0 unless the script crashes, so it does not reflect the verdict.
- It also prints the full command and raw output of every transaction (`Debug - ...`), so stdout gets very long.

**Notes / caveats**:

- **You must run it as root.** It uses the same `ps -ef` regex for `root` as `non_blocking_commands.py`, so it times out as any other user. The same early-match issue with its own helper shell applies.
- **Fragile shell quoting.** Many commands contain single quotes (`'Hello'`, `' World'`, `'Palermo'`), which break out of the `echo '...'` wrapper. The shell strips those quotes, so values are effectively sent unquoted, and spaces inside them can be lost (for example, `' World'` becomes `World`). It still runs, but not exactly as written.
- **Per-command labels are approximate.** Output lines are matched to commands by line number. `EXEC` returns multi-line output, so the labels don't line up with the real replies.
- **Groups with no leaks at all can be missed.** When valgrind finds no leaks at all, it prints no `LEAK SUMMARY`, so that group adds no `definitely lost:` line. If no group produces one, the final verdict is `Failed`. Only the last 15 lines of each valgrind log are searched.
- **Report crash after a startup failure.** As in `non_blocking_commands.py`, a startup, `PING` or shutdown timeout makes the result lack `results` and `transaction_results`. Writing the report then fails with a `KeyError`, before any verdict is printed.
- **Error replies are expected and never checked.** Many queued commands deliberately error or do nothing, for example duplicate XGROUP CREATE/DESTROY, XDEL of an already deleted ID, and BLPOP/BRPOP on zset keys.

---

## address-sanitiser-scripts/

These scripts start a locally built `envoy-static` binary, which is expected to be an AddressSanitizer (ASan) build, with an `envoy.yaml` you supply. They then send Redis commands through the proxy with `redis-cli`. They check that Envoy is still running and still answers `PING`: the Python script checks before every command, and the shell script checks after every group. A crash, or a memory error that ASan turns into a crash, therefore shows up as a failure. Neither script reads the Envoy log for ASan reports, so you have to check the log yourself.

### `non_blocking_commands.py`

- **Purpose**: Starts Envoy and sends a long fixed list of Redis commands through the proxy one at a time. Before every command it checks that Envoy is running and that the proxy answers `PING`. This stresses how the `redis_proxy` filter parses and routes many different command shapes.
- **What it tests** (grouped by family below; the script runs them in a different, mixed order):
  - Streams: XADD (MAXLEN ~, NOMKSTREAM, MINID ~, LIMIT), XRANGE (COUNT), XREVRANGE (COUNT), XLEN, XDEL, XTRIM (MAXLEN / MINID, ~, LIMIT), XGROUP (CREATE, CREATECONSUMER, SETID with ENTRIESREAD, DESTROY, DELCONSUMER, MKSTREAM), XREADGROUP (COUNT, BLOCK 5000, NOACK, multiple streams, explicit ID), XPENDING (summary, range, consumer, IDLE), XCLAIM (JUSTID, FORCE, IDLE, RETRYCOUNT, TIME), XAUTOCLAIM (COUNT, JUSTID), XINFO (STREAM, STREAM FULL, GROUPS, CONSUMERS)
  - Sets: SADD, SMEMBERS, SREM, SMISMEMBER, SUNION, SDIFF, SINTER, SUNIONSTORE, SDIFFSTORE, SINTERSTORE
  - Sorted sets: ZUNIONSTORE / ZINTERSTORE (WEIGHTS, AGGREGATE), ZMSCORE, ZRANGESTORE (BYSCORE, REV, LIMIT), ZUNION (WEIGHTS, AGGREGATE), ZDIFF (WITHSCORES), ZDIFFSTORE, ZINTER (WITHSCORES, WEIGHTS, AGGREGATE), ZRANDMEMBER (count, negative count, WITHSCORES)
  - Blocking list / zset commands: BRPOPLPUSH, BZPOPMAX, BZPOPMIN, BLPOP, BRPOP, BLMOVE. Every group except BLMOVE is meant to run setup pushes first (LPUSH, RPUSH, ZADD), but see the missing-commas caveat below.
  - Geo: GEORADIUS, GEORADIUSBYMEMBER (WITHDIST / WITHCOORD / WITHHASH, COUNT, ASC/DESC, STORE), GEOSEARCH, GEOSEARCHSTORE (FROMLONLAT / FROMMEMBER, BYBOX / BYRADIUS, ASC, COUNT, WITHDIST / WITHCOORD / WITHHASH, STOREDIST)
  - HyperLogLog: PFMERGE
  - Hashes: HRANDFIELD (no count, count, negative count, WITHVALUES)
  - Strings / keys: GETDEL, GETEX (no option, EX, PX, EXAT, PXAT, PERSIST), MSETNX, SUBSTR, BITOP (AND/OR/XOR/NOT), RENAME, RENAMENX, SORT (DESC, ALPHA, LIMIT, BY, GET, STORE), KEYS, SCAN (MATCH, TYPE, COUNT), RANDOMKEY
  - Lists: LPOS (RANK, COUNT, MAXLEN)
  - Pub/Sub introspection: PUBSUB CHANNELS (with and without a pattern), NUMSUB, NUMPAT
  - Scripting: SCRIPT LOAD, EXISTS, FLUSH, KILL
  - Server / connection / admin: FLUSHALL (and ASYNC), SLOWLOG (GET, GET 10, LEN, RESET), CONFIG (GET, SET maxmemory, RESETSTAT), CLIENT (LIST, GETNAME, SETNAME, KILL, PAUSE), INFO (and INFO memory), CLUSTER (INFO, NODES, SLOTS, KEYSLOT), SELECT 0/1, HELLO (2, 3 AUTH, 3 SETNAME), UNWATCH
- **How it runs**:
  - The script takes no CLI arguments, environment variables or config file. Everything is hardcoded:
    - The Envoy command is `./bazel-bin/source/exe/envoy-static -c envoy.yaml`, started in the background. Its stdout and stderr go to `envoy_logs.txt`.
    - Proxy address: `redis-cli -p 1999`. With no `-h`, redis-cli uses its default host, 127.0.0.1. Cluster mode (`-c`) is not used.
    - Every command runs as `redis-cli -p 1999 <command>` through `/bin/sh` (`shell=True`).
  - Prerequisites:
    - Python 3.6 or later, standard library only (`subprocess`, `time`, `re`, `sys`).
    - `redis-cli` on `PATH`, plus `ps` and `grep`.
    - An Envoy build at `bazel-bin/source/exe/envoy-static`, relative to the current directory. It should be ASan-instrumented for this suite to be useful.
    - An `envoy.yaml` in the current directory with a `redis_proxy` listener on port 1999 pointing at your Redis cluster.
    - Envoy must show up in `ps -ef` with the user name `root` (see Notes).
  - Example:

    ```bash
    cd /path/to/envoy-source        # contains bazel-bin/ and your envoy.yaml
    python3 /path/to/address-sanitiser-scripts/non_blocking_commands.py
    ```

- **Pass/fail & output**:
  - **Startup:** waits up to 600 s for an `envoy-static` process, then up to 600 s for `PONG`. If either times out, it prints `Error: Timed out ...` and then `Failed to start Envoy or connect to Redis`, and exits with code 1.
  - **Each command:** the full health check runs first, so a dead proxy can take up to 600 s + 600 s to be noticed. Then the command runs.
  - **What counts as a failure:** a failed health check, or anything at all written to redis-cli's **stderr**. On the first failure the script prints the report so far, ending with the failing entry, and exits with code 1.
  - **Report:** a single line with one `<group> - Success` or `<group> - Failed` entry per command (not per group). Entries are joined by a literal `\` (backslash and space).
  - **Success:** the report line ends with `Test completed` and the script exits with code 0.
  - **Console noise:** every health check also prints `Debug - PS output: ...` lines.
  - ASan findings go to `envoy_logs.txt`, and you must check them by hand.
- **Notes / caveats**:
  - **`envoy.yaml` is not included.** You must supply it.
  - **Weak liveness check.** `wait_for_envoy` runs `ps -ef | grep 'envoy-static'` and accepts a match only if the regex `root\s+(\d+)\s+.*envoy-static` matches, i.e. the user column reads `root`.
    - If neither Envoy nor the `grep` runs as `root`, the check loops until the 600 s timeout and then fails. This also happens when `ps` shows numeric UIDs.
    - When you run the script as root, the `grep envoy-static` process matches its own pattern and satisfies the regex. The "Envoy is running" check then always passes, even if Envoy is dead. In practice, crashes are caught by the `PING` check.
  - **Error replies don't fail the test.** The redis-cli exit code is never checked. Server error replies, such as unsupported commands, cross-slot errors or bad syntax, count as failures only if your redis-cli version writes them to stderr. Otherwise they are reported as `Success`.
  - **Some commands are invalid as written.** They exercise the proxy's error paths rather than real behaviour. Examples:
    - `xadd audit_log LIMIT 1000 *` (LIMIT without MAXLEN/MINID).
    - `geosearch` / `geosearchstore ... fromlon <x> fromlat <y>` (not a valid option).
    - `xclaim ... ID1 ID2 ID3`.
  - **Missing commas.** In the `brpoplpush`, `bzpopmax`, `bzpopmin`, `blpop` and `brpop` groups, the setup strings and the first blocking command have no commas between them. Python joins them into one string, so each group sends one merged command:
    - For `brpoplpush`, `blpop` and `brpop`, it becomes a single LPUSH or RPUSH with many extra values. The first blocking command (the one with timeout `0`) is never sent.
    - For `bzpopmax` and `bzpopmin`, it becomes a single ZADD with a non-numeric score, which gets an error reply.
    - Only the second blocking command in each group (timeout `5`) is sent on its own.
  - **Shell interpretation.** Commands run through `/bin/sh`:
    - These unquoted `*` arguments can be glob-expanded against files in the current directory: `*` in every XADD (`xadd <stream> * ...`), `config get *`, `keys *`, and the `user:*`, `product:*` and `user:*:notifications` patterns.
    - In `sort user_ids BY user:*->age` and `sort user_ids GET user:*->name`, the shell treats `>` as a redirect. The commands are sent truncated as `... user:*-`, and their output goes to files named `age` and `name` in the current directory.
  - **Blocking commands can hang.** Despite the file name, the script sends blocking commands, and there is no per-command timeout.
    - `blmove source destination left right 0` runs after FLUSHALL, so `source` is empty. If the proxy forwards it, it can block indefinitely.
    - The commands with timeout `5` and `XREADGROUP ... BLOCK 5000` can each block for about 5 s.
  - **Destructive commands.** The script runs FLUSHALL (and ASYNC), SCRIPT FLUSH, SCRIPT KILL, CONFIG SET maxmemory 2GB, CONFIG RESETSTAT, SLOWLOG RESET, CLIENT KILL 127.0.0.1:52500 and CLIENT PAUSE 5000. Use a disposable cluster.
  - **Hardcoded credentials.** `hello 3 AUTH admin StrongPassword123` uses a hardcoded placeholder username and password.
  - **Placeholder values.** Many commands use keys or IDs that don't exist, such as `ID1 ID2 ID3` and fixed stream IDs. The aim is to exercise the proxy, not to check results.
  - **Duplicates and dead code.**
    - The groups `sunionstore`, `smismember` and `xclaim` each appear twice.
    - An `xreadgroup` group is commented out.
    - In `xreadgroup`, `"> >"` is passed as one argument, which is malformed.
  - **Python 3.12+ warning.** `"\ ".join(...)` uses an invalid escape sequence. Python 3.12 and later print a `SyntaxWarning`, but the script still runs.
  - **Envoy keeps running.** The script never stops Envoy, so it is still running in the background afterwards.

### `blocking_commands.sh`

- **Purpose**: Starts Envoy and runs four groups of commands through the proxy, focused on blocking and subscription commands: Pub/Sub, XREAD, XREADGROUP, plus a few basic commands. It checks that Envoy is alive and answering `PING` after each group. At the end it stops Envoy with SIGTERM, so ASan's exit-time output can be written to the log.
- **What it tests**:
  - `pubsub`:
    1. Background `PSUBSCRIBE test_*` and `SUBSCRIBE test_channel`, each run under `timeout 5s`, with 2 s sleeps.
    2. `PUBSUB CHANNELS`, then 5 × `PUBLISH test_channel "Message N"`.
    3. `PUBSUB NUMSUB test_channel`, `PUBSUB NUMPAT`, `PUBSUB CHANNELS`.
    4. `PUNSUBSCRIBE test_*`, `UNSUBSCRIBE test_channel`, then `PUBSUB CHANNELS` again.
  - `xread`: 2 × `XADD mystream * ...`, then `XREAD COUNT 2 STREAMS mystream 0-0`, then `XREAD BLOCK 5000 COUNT 1 STREAMS mystream <id from 2nd XADD>` under `timeout 5s`.
  - `xreadgroup`:
    1. Setup: `XADD` plus `XGROUP CREATE ... 0-0 MKSTREAM` for `order_stream`, `notification_stream`, `sensor_data`, `event_log1`, `event_log2` and `audit_log`.
    2. `XREADGROUP` with COUNT, BLOCK 5000 (under `timeout 5s`), NOACK, two streams with `">" ">"`, and an explicit ID `0-0`.
  - `other`: SET, GET, HSET, HGET.
- **How it runs**:
  - The script takes no CLI arguments or environment variables. To change anything, edit the variables at the top of the script:
    - `ENVOY_BINARY=./bazel-bin/source/exe/envoy-static`
    - `ENVOY_CONFIG=envoy.yaml`
    - `REDIS_PORT=1999`
    - `CHANNEL=test_channel`
    - `PATTERN=test_*`
  - Envoy is started in the background as `$ENVOY_BINARY -c $ENVOY_CONFIG --log-level debug`. Its stdout and stderr go to `envoy_console_log.log`.
  - Every command is sent as `redis-cli -c -h 127.0.0.1 -p $REDIS_PORT ...` (cluster mode on).
  - Prerequisites:
    - bash.
    - `redis-cli`, `pgrep`, `kill`, `date` and `timeout`. `timeout` is from GNU coreutils; on macOS, install coreutils and make `timeout` available on `PATH`.
    - The Envoy binary and an `envoy.yaml` with a `redis_proxy` listener on port 1999, both relative to the current directory.
  - Example:

    ```bash
    cd /path/to/envoy-source        # contains bazel-bin/ and your envoy.yaml
    bash /path/to/address-sanitiser-scripts/blocking_commands.sh
    ```

- **Pass/fail & output**:
  - **Startup:** waits up to 600 s for an `envoy-static` process (via `pgrep -f`), then up to 600 s for `PONG`.
    - If either check fails, it prints `Error: Envoy failed to start` or `Error: Redis did not respond in time` and kills Envoy.
    - It then prints `Error: Unable to connect to Redis` and exits with code 1.
  - **Each command:** `execute_redis_command` makes up to 3 attempts in total, 1 s apart, whenever redis-cli exits non-zero.
    - Each failed attempt prints `Command failed, retrying... (Attempt N)` to stdout.
    - After the third failure it prints `Error: Redis command failed after 3 attempts: <output>` to stderr and returns 1.
  - **After each group:** the Envoy and `PING` check runs again.
    - If the check fails, Envoy is killed and the script prints `Error: Envoy or Redis failed after <group>`.
    - It then prints `Error: Tests for <group> - Failed` (`Error: Tests for other commands - Failed` for the last group).
    - The script carries on with the next group.
  - **Shutdown:**
    1. Sends SIGTERM to `$ENVOY_PID` and waits up to 900 s.
    2. If Envoy hasn't stopped by then, prints `Error: Failed to terminate Envoy` and sends `kill -9`.
    3. Prints `Completed testing for all commands - Success`.
  - **Exit code** is 0 whenever startup succeeded, even if some groups failed. Look for `Error:` lines in the console output, and read `envoy_console_log.log` for ASan reports.
- **Notes / caveats**:
  - **`envoy.yaml` is not included.** You must supply it.
  - **Command failures never fail a group.** `run_test_group` ignores the return value of the group function, so a group is reported as failed only when the post-group health check fails.
    - Inside `pubsub`, `|| return 1` only stops the rest of the pubsub sequence early.
    - Even that triggers only on some failures: a helper function's status comes from its last command, and several helpers end with `sleep`.
  - **Final message is always "Success".** The last line prints `Success` regardless of earlier failures.
  - **Unquoted `*` in XADD.** `execute_redis_command XADD <stream> * ...` passes `*` unquoted, so bash glob-expands it against the current directory. In a non-empty directory, such as the Envoy source tree, XADD receives file names instead of `*` and fails, which also affects the stream and group setup.
  - **Garbage stream ID is possible.** `stream_id` captures all stdout of `execute_redis_command`, including any `Command failed, retrying...` lines. If that XADD fails, the following `XREAD BLOCK` gets a garbage ID.
  - **Pattern subscriber expires early.** The `PSUBSCRIBE` client's `timeout 5s` has already expired (after about 6 s of sleeps) before the first `PUBLISH`, so pattern delivery is not really exercised. The channel subscriber is still alive for roughly the first second of publishing.
  - **Unsubscribe doesn't touch the subscribers.** `PUNSUBSCRIBE` / `UNSUBSCRIBE` are sent on a new connection, so the background subscribers are unaffected. They end only when their `timeout 5s` expires, and their output is mixed into the console output.
  - **Envoy is not restarted after a failed health check.** It is killed, and later groups then run against no proxy, each waiting up to 600 s for Envoy before failing.
  - **PID can be overwritten.** `ENVOY_PID` is first set from `$!` and then replaced by the output of `pgrep -f ".*envoy-static"`. That can return several PIDs, and the final `kill` would then signal every `envoy-static` process on the host.
  - **Unused variables.** `LOG_FILE="envoy_asan_build.log"`, `PSUB_PID` and `SUB_PID` are set but never used.

---

## Deploy a Valkey Cluster on Kubernetes

Run the deployment from the repository root with Helm and `kubectl` installed. Set your current Kubernetes context and namespace to the test environment first.

```bash
(cd k8s && ./deploy-valkey-cluster.sh)
kubectl get pods -n valkey-operator-system
kubectl get valkeycluster benchmark-cluster
kubectl get valkeynodes -o wide
```

The script installs the Valkey Operator in `valkey-operator-system` and applies the `benchmark-cluster` resource in your current namespace. Run it from `k8s/` because it uses a relative path to the manifest. The manifest requests three shards with zero replicas per shard. Check that the operator is running and the Valkey nodes are ready before starting a workload. [Deployment script](k8s/deploy-valkey-cluster.sh) · [Cluster manifest](k8s/cr/valkey-cluster.yaml)

The deployment provides the Valkey backend. Configure your proxy to use that backend before running the benchmark or pub/sub scripts. Run the client-kill script from a shell with `kubectl` access to the backend namespace.

## endurance-test-scripts/

Long-running load and fault-injection scripts. Each one stresses the proxy for a long time (or forever) so you can watch its memory, connection count, error rate and crash behaviour. None of them checks results automatically and none returns a pass/fail exit code. You judge the run from the logs and from the proxy's own metrics.

### `endurance_automation.sh`

Runs one `valkey-benchmark` process per command. It reads arguments from a commands file, skips blank lines and full-line comments, and preserves quoted arguments without shell expansion. Install `valkey-cli` and `valkey-benchmark` where the script runs.

```bash
./endurance_automation.sh '' 127.0.0.1 7777 500 200 result_cx commands.txt
```

The seven positional arguments are the password, proxy host, proxy port, per-command request rate, connections per command, result prefix, and commands file. Pass an empty password to skip authentication. Set `BENCHMARK_REQUESTS` to override the benchmark client's default total requests per command, and `BENCHMARK_START_DELAY` to override the two-second delay between starts.

At startup, the script uses an unauthenticated `valkey-cli` connection to check for `order_stream`. If the stream is absent, it creates the `order_processors` group at `$`. If the stream already exists but lacks the group, create it before running the bundled workload.

```bash
valkey-cli -h 127.0.0.1 -p 7777 XGROUP CREATE order_stream order_processors '$' MKSTREAM
```

Each benchmark writes CSV output and diagnostics to `results_endurance/<result_prefix>_<line_number>.log`. The script waits for the jobs, reports throughput and p50 latency, and exits with status 1 if a benchmark fails. [Script](endurance-test-scripts/endurance_automation.sh)

### `commands.txt`

The bundled workload contains 94 commands for `endurance_automation.sh`. It covers strings, hashes, lists, sets, sorted sets, HyperLogLog, geo, bitmaps, streams, pub/sub, key management, scanning, and server and cluster commands. [Workload](endurance-test-scripts/commands.txt)

Benchmarks run concurrently, so operations on shared keys can overlap. Geo queries use `locations` without populating it. Stream commands use `order_processors` on `order_stream`, and `XCLAIM` uses a fixed entry ID. Server and cluster commands require support in the proxy build under test.

### `endurance_streams.sh`

Runs 14 benchmarks covering streams, lists, bitmaps, and Lua scripting. Setup uses `valkey-cli` to load the Lua script for `EVALSHA`, create or reuse the `mygroup` consumer group, and add an entry whose ID is passed to `XDEL`. The workloads use `valkey-benchmark`.

```bash
PROXY_HOST=127.0.0.1 PROXY_PORT=7777 VALKEY_PWD='' KEY_PREFIX=streams-test: \
  ./endurance_streams.sh
```

- `PROXY_HOST` is required. `PROXY_PORT` defaults to `7777`. Set `VALKEY_PWD` for an authenticated endpoint.
- `REQUESTS` sets the per-benchmark rate in requests per second and defaults to `2000`. `CONNECTIONS` defaults to `200` per benchmark.
- `KEY_PREFIX` is optional and is prepended to `mylist`, `mykey`, and `mystream`.

Jobs start two seconds apart and the script waits for them. It overwrites `endurance_streams_result.csv` alongside the script and appends the last output line from each benchmark. Setup failures cause a nonzero exit. Inspect stderr and the CSV for individual benchmark failures because the parent script does not collect those exit statuses. [Script](endurance-test-scripts/endurance_streams.sh)

### `endurance_pubsub.sh`

Runs a pub/sub soak test with `valkey-cli` and OpenSSL. Each iteration opens channel and pattern subscriptions, publishes to the generated channels, and runs random subscribe, unsubscribe, and publish operations while publishing is active.

```bash
VALKEY_HOST=127.0.0.1 VALKEY_PORT=7777 VALKEY_PWD='' \
  NUM_CHANNELS=10 NUM_PATTERNS=5 PUBLISH_DURATION=10 ITERATIONS=1 \
  ./endurance_pubsub.sh
```

| Variable | Default |
| --- | --- |
| `VALKEY_HOST` | Required |
| `VALKEY_PORT` | `6379` |
| `VALKEY_PWD` | Empty for an unauthenticated proxy |
| `NUM_CHANNELS` | `7000` |
| `NUM_PATTERNS` | `3000` |
| `PUBLISH_DURATION` | `1800` seconds per iteration |
| `PUBLISH_IOPS` | `100` messages per one-second pause |
| `RANDOM_OPERATIONS_INTERVAL` | `10` seconds |
| `ITERATIONS` | `2000` |

The script reports progress and discards subscriber output. Watch proxy metrics for the effect of the load. Unsubscribe commands use fresh connections, so the original subscriber processes can persist across iterations. The generated `pattern_*` subscriptions do not match the `channel_*` destinations. Default settings require process and file-descriptor limits that can support at least 10,000 concurrent subscribers per iteration. [Script](endurance-test-scripts/endurance_pubsub.sh)

### `endurance_client_kill.sh`

Injects backend connection failures while another workload runs through the proxy. It requires `kubectl` access to list `ValkeyNode` resources and exec into the selected pods. Each cycle reads `.status.podIP` and `.status.podName` from nodes whose `.status.role` is `primary`. In each pod's `server` container, it runs `valkey-cli` against that pod's IP on port `6379` and issues `CLIENT KILL TYPE normal` and `CLIENT KILL TYPE pubsub`.

```bash
NAMESPACE=default VALKEY_PASSWORD='' ./endurance_client_kill.sh
```

Set `NAMESPACE` to the namespace where you deployed the cluster. `VALKEY_PASSWORD` defaults to empty and is passed to the backend client with `--user default`. The script selects nodes by their reported role. It prints the selected pods and kill results, then sleeps for 900 seconds (15 minutes) and repeats until stopped. The kill commands affect all clients of the selected types on those nodes. [Script](endurance-test-scripts/endurance_client_kill.sh)
