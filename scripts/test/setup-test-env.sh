#!/bin/bash
# setup-test-env.sh - Orchestrate test environment setup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== Setting up Anvil Test Environment ==="

# Start infrastructure (Anvil, Postgres, Valkey)
echo "1. Starting Anvil, Postgres, and Valkey..."
docker-compose -f "${PROJECT_ROOT}/docker-compose.test.yml" up -d anvil postgres valkey

# Wait for services to be healthy
echo "2. Waiting for services to be ready..."
sleep 5

# Deploy contracts (one-shot container)
echo "3. Deploying contracts and generating events..."
docker-compose -f "${PROJECT_ROOT}/docker-compose.test.yml" up contract-deployer

# Check if deployment succeeded
if [ ! -f "${PROJECT_ROOT}/deployed-addresses.json" ]; then
    echo "✗ Error: Contract deployment failed"
    docker-compose -f "${PROJECT_ROOT}/docker-compose.test.yml" logs contract-deployer
    exit 1
fi

# Extract deployed addresses
TOKEN1_ADDRESS=$(jq -r '.token1' "${PROJECT_ROOT}/deployed-addresses.json")
TOKEN2_ADDRESS=$(jq -r '.token2' "${PROJECT_ROOT}/deployed-addresses.json")

echo "4. Generating test configuration..."
# Generate config.test.json
cat > "${PROJECT_ROOT}/config/config.test.json" <<EOF
{
  "api": {
    "port": 8081,
    "ttl": 300
  },
  "indexer": {
    "rpc_url": "http://anvil:8545",
    "contract_addresses": [
      "${TOKEN1_ADDRESS}",
      "${TOKEN2_ADDRESS}"
    ],
    "abi": [
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "name": "from",
            "type": "address"
          },
          {
            "indexed": true,
            "name": "to",
            "type": "address"
          },
          {
            "indexed": false,
            "name": "value",
            "type": "uint256"
          }
        ],
        "name": "Transfer",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "name": "owner",
            "type": "address"
          },
          {
            "indexed": true,
            "name": "spender",
            "type": "address"
          },
          {
            "indexed": false,
            "name": "value",
            "type": "uint256"
          }
        ],
        "name": "Approval",
        "type": "event"
      }
    ],
    "event_names": ["Transfer", "Approval"],
    "confirmed_after": 1,
    "offset_block_number": 0,
    "status_file_path": "/var/lib/eth-indexer/test-state/status.json"
  },
  "postgres": {
    "host": "postgres",
    "port": 5432,
    "database": "eth_indexer_test",
    "user": "indexer",
    "password": "indexer_password",
    "max_connections": 10
  },
  "redis": {
    "host": "valkey",
    "port": 6379,
    "password": "",
    "db": 0
  }
}
EOF

echo "5. Starting indexer and api-server..."
docker-compose -f "${PROJECT_ROOT}/docker-compose.test.yml" up -d indexer api-server

echo ""
echo "=== Test Environment Ready ==="
echo "  Anvil RPC:        http://localhost:8545"
echo "  Indexer:          http://localhost:8081"
echo "  API Server:       http://localhost:8082"
echo "  Postgres:         localhost:5434"
echo "  Valkey:           localhost:6380"
echo "  Token1 (TUSDC):   ${TOKEN1_ADDRESS}"
echo "  Token2 (TUSDT):   ${TOKEN2_ADDRESS}"
echo ""
echo "Run tests with:    make test-integration"
echo "View logs with:    docker-compose -f docker-compose.test.yml logs -f"
echo "Teardown with:     make test-env-down"
