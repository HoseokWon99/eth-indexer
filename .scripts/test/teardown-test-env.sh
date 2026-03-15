#!/bin/bash
# teardown-test-env.sh - Clean up test environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== Tearing Down Test Environment ==="

# Stop and remove all containers
echo "1. Stopping Docker containers..."
docker-compose -f "${PROJECT_ROOT}/docker-compose.test.yml" down -v

# Remove generated files
echo "2. Cleaning up generated files..."
rm -f "${PROJECT_ROOT}/config/config.test.json"
rm -f "${PROJECT_ROOT}/deployed-addresses.json"
rm -rf "${PROJECT_ROOT}/test-state"

# Clean contract artifacts (optional - keep for faster rebuilds)
# rm -rf "${PROJECT_ROOT}/test/contracts/out"
# rm -rf "${PROJECT_ROOT}/test/contracts/broadcast"

echo "✓ Test environment cleaned up"
