#!/bin/bash
# generate-events.sh - Generate test events from deployed contracts

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONTRACTS_DIR="${PROJECT_ROOT}/test/contracts"

# Load addresses from deployed-addresses.json if not set in environment
ADDRESSES_FILE="${PROJECT_ROOT}/deployed-addresses.json"
if [ -z "${TOKEN1_ADDRESS}" ] || [ -z "${TOKEN2_ADDRESS}" ]; then
    if [ ! -f "${ADDRESSES_FILE}" ]; then
        echo "✗ Error: TOKEN1_ADDRESS/TOKEN2_ADDRESS not set and ${ADDRESSES_FILE} not found"
        echo "  Run deploy-contracts.sh first"
        exit 1
    fi
    TOKEN1_ADDRESS=$(jq -r '.token1' "${ADDRESSES_FILE}")
    TOKEN2_ADDRESS=$(jq -r '.token2' "${ADDRESSES_FILE}")
fi

export TOKEN1_ADDRESS
export TOKEN2_ADDRESS

# Mnemonic for deterministic key derivation (Anvil default)
export MNEMONIC="${MNEMONIC:-test test test test test test test test test test test junk}"

cd "${CONTRACTS_DIR}"

echo "Generating test events..."
echo "  Token1: ${TOKEN1_ADDRESS}"
echo "  Token2: ${TOKEN2_ADDRESS}"
forge script script/GenerateEvents.s.sol:GenerateEvents \
    --rpc-url "${RPC_URL:-http://localhost:8545}" \
    --broadcast \
    --legacy \
    -vv

echo "✓ Event generation complete"
