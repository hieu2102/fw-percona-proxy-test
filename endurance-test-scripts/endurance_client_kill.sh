#!/bin/bash

# Configuration
NAMESPACE="${NAMESPACE:?Set NAMESPACE to the k8s namespace of the Redis cluster}"
LABEL_SELECTOR="${LABEL_SELECTOR:-role=Master}"
REDIS_PASSWORD="${REDIS_PASSWORD:?Set REDIS_PASSWORD}"
REDIS_PORT="6379"
INTERVAL_MINUTES=900

# Function to kill Redis clients
kill_redis_clients() {
    local pod_ip=$1
    local client_types=("normal" "pubsub")

    for client_type in "${client_types[@]}"; do
        echo "Killing $client_type clients on $pod_ip"
        kubectl exec -n $NAMESPACE $pod_name -- \
            redis-cli -h $pod_ip -p $REDIS_PORT -a $REDIS_PASSWORD \
            CLIENT KILL TYPE $client_type
    done
}

# Main loop
while true; do
    echo "Starting client kill process at $(date)"

    # Get pod IPs
    pod_list=$(kubectl get pods -n $NAMESPACE -l $LABEL_SELECTOR -o jsonpath='{range .items[*]}{.status.podIP}{"\t"}{.metadata.name}{"\n"}{end}')

    # Process each pod
    while IFS=$'\t' read -r pod_ip pod_name; do
        echo "Processing pod: $pod_name ($pod_ip)"
        kill_redis_clients $pod_ip
    done <<< "$pod_list"

    echo "Finished client kill process at $(date)"
    echo "Waiting for $INTERVAL_MINUTES minutes before next iteration..."
    sleep $INTERVAL_MINUTES
done