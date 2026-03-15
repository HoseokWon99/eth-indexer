#!/bin/bash
# wait-for-rpc.sh - Wait for Anvil RPC to be ready

set -e

RPC_URL="${1:-http://localhost:8545}"
MAX_RETRIES=30
RETRY_INTERVAL=2

echo "Waiting for Anvil RPC at ${RPC_URL}..."

for i in $(seq 1 ${MAX_RETRIES}); do
    if cast client --rpc-url "${RPC_URL}" >/dev/null 2>&1; then
        echo "✓ Anvil RPC is ready (attempt ${i}/${MAX_RETRIES})"
        exit 0
    fi
    echo "  Waiting for RPC... (attempt ${i}/${MAX_RETRIES})"
    sleep ${RETRY_INTERVAL}
done

echo "✗ Error: Anvil RPC not ready after ${MAX_RETRIES} attempts"
exit 1
