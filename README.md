# fw-percona-proxy-test

Test scripts for validating an [Envoy](https://www.envoyproxy.io/) Redis proxy (`envoy.filters.network.redis_proxy`) in front of a Redis / Valkey cluster: functional command coverage, negative tests, memory-leak checks (Valgrind / AddressSanitizer) and long-running endurance tests.

See **[TEST_SCRIPTS.md](TEST_SCRIPTS.md)** for a per-script description of what each test covers and how to run it.

## Layout

| Folder | What it contains |
|---|---|
| [`envoy_commands_sanity/`](envoy_commands_sanity) | Functional sanity suites for Redis commands through the proxy, plus pub/sub, MULTI/EXEC transaction and negative (error-path) tests. `*_valkey8.sh` variants cover Valkey 8 behaviour. |
| [`valgrind-memory-leak-scripts/`](valgrind-memory-leak-scripts) | Drives blocking, non-blocking and transaction workloads against an Envoy binary running under Valgrind to detect leaks. |
| [`address-sanitiser-scripts/`](address-sanitiser-scripts) | Same style of workload for an Envoy build compiled with AddressSanitizer. |
| [`endurance-test-scripts/`](endurance-test-scripts) | Long-running load (redis-benchmark-go, pub/sub churn, streams) and periodic client kills to check proxy stability over time. |

## Configuration

No connection details are hard-coded. Each script takes them from environment variables, a config file or command-line arguments. The script fails fast if a required value is missing.

```bash
# Standalone scripts (pubsub / transaction / negative / endurance)
export REDIS_HOST=<proxy-host> REDIS_PORT=<proxy-port> REDIS_PASSWORD=<password>
./envoy_commands_sanity/transaction_commands.sh

# Kubernetes-based sanity suites read ./test_params_envoy.cfg from the working directory
cd envoy_commands_sanity && $EDITOR test_params_envoy.cfg && ./envoy_commands_sanity.sh
```

The exact variables for each script are listed in [TEST_SCRIPTS.md](TEST_SCRIPTS.md).

## Prerequisites

Depending on the script: `bash`, `redis-cli`, `kubectl` (for the Kubernetes-based suites), Python 3 (standard library only), [`redis-benchmark-go`](https://github.com/redis-performance/redis-benchmark-go), `valgrind`, and an Envoy build (`bazel-bin/source/exe/envoy-static`, optionally built with ASan) together with your own `envoy.yaml`.

## License

[Apache License 2.0](LICENSE)
