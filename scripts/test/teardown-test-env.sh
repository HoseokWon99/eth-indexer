#!/bin/bash
# teardown-test-env.sh - Clean up test environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== Tearing Down Test Environment ==="

echo "1. Stopping Docker containers and removing volumes..."
docker-compose -f "${PROJECT_ROOT}/docker-compose.test.yml" down -v

echo "2. Cleaning up generated files..."
rm -rf "${PROJECT_ROOT}/test-state"

echo "✓ Test environment cleaned up"
