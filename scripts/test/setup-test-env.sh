#!/bin/bash
# setup-test-env.sh - Start test environment for manual testing / make test-integration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE="docker-compose -f ${PROJECT_ROOT}/docker-compose.test.yml"

echo "=== Setting up Test Environment ==="

echo "1. Starting infrastructure (Anvil, Postgres, Valkey)..."
$COMPOSE up -d anvil postgres valkey

echo "2. Deploying contracts..."
$COMPOSE up contract-deployer

echo "3. Generating events..."
$COMPOSE up event-generator

echo "4. Starting indexer and api-server..."
$COMPOSE up -d indexer api-server

echo "5. Waiting for api-server to be healthy..."
until curl -sf http://localhost:8082/health > /dev/null; do sleep 2; done

echo ""
echo "=== Test Environment Ready ==="
echo "  Anvil RPC:   http://localhost:8545"
echo "  Indexer:     http://localhost:8081  (GET /health, GET /state)"
echo "  API Server:  http://localhost:8082  (GET /search/{topic})"
echo "  Postgres:    localhost:5434"
echo "  Valkey:      localhost:6380"
echo ""
echo "Run tests:  make test-integration"
echo "View logs:  docker-compose -f docker-compose.test.yml logs -f"
echo "Teardown:   make test-env-down"
