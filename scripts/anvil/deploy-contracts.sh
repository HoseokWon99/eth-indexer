#!/bin/bash
# deploy-contracts.sh - Deploy test contracts

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONTRACTS_DIR="${PROJECT_ROOT}/test/contracts"

# Wait for Anvil RPC
echo "Waiting for Anvil RPC..."
"${SCRIPT_DIR}/wait-for-rpc.sh" "${RPC_URL:-http://anvil:8545}"

# Export private key from deterministic mnemonic
# Mnemonic: "test test test test test test test test test test test junk"
# Account 0 private key
export PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

cd "${CONTRACTS_DIR}"

# Deploy contracts
echo "Deploying test contracts..."
forge script script/Deploy.s.sol:Deploy \
    --rpc-url "${RPC_URL:-http://anvil:8545}" \
    --broadcast \
    --legacy \
    -vv

# Extract deployed addresses from broadcast output
CHAIN_ID=$(cast chain-id --rpc-url "${RPC_URL:-http://anvil:8545}")
BROADCAST_DIR="${CONTRACTS_DIR}/broadcast/Deploy.s.sol/${CHAIN_ID}"
if [ ! -d "${BROADCAST_DIR}" ]; then
    echo "✗ Error: Broadcast directory not found: ${BROADCAST_DIR}"
    echo "  forge script may have failed — check output above"
    exit 1
fi

LATEST_RUN="${BROADCAST_DIR}/run-latest.json"
if [ ! -f "${LATEST_RUN}" ]; then
    echo "✗ Error: Could not find run-latest.json in ${BROADCAST_DIR}"
    exit 1
fi

TOKEN1_ADDRESS=$(jq -r '.transactions[0].contractAddress' "${LATEST_RUN}")
TOKEN2_ADDRESS=$(jq -r '.transactions[1].contractAddress' "${LATEST_RUN}")

echo "Deployed contracts:"
echo "  Token1 (TUSDC): ${TOKEN1_ADDRESS}"
echo "  Token2 (TUSDT): ${TOKEN2_ADDRESS}"

# Save addresses to file
cat > "${PROJECT_ROOT}/deployed-addresses.json" <<EOF
{
  "token1": "${TOKEN1_ADDRESS}",
  "token2": "${TOKEN2_ADDRESS}"
}
EOF

echo "✓ Contract deployment complete"
echo "  Deployed addresses saved to: ${PROJECT_ROOT}/deployed-addresses.json"
