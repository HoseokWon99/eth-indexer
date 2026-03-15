# Testing Guide

This guide covers all testing strategies for eth-indexer, from unit tests to full integration tests with Anvil.

## Quick Start

```bash
# Install dependencies
cd test && npm install

# Run all tests (unit + integration E2E)
make test-all

# Or run separately:
make test-unit         # Go unit tests
make test-e2e          # Full integration E2E (Anvil)
```

## Test Types

### 1. Unit Tests (Go)

Fast, focused tests for individual Go packages.

```bash
make test-unit
# or
go test -v ./...
```

**What it tests:**
- Individual function logic
- Edge cases and error handling
- Data transformations
- No external dependencies

### 2. Integration Tests (Anvil + Docker)

Full-stack tests with local Ethereum blockchain, contracts, and indexer.

```bash
# Full E2E cycle (recommended)
make test-e2e

# Manual control
make test-env-up        # Start environment
make test-integration   # Run tests
make test-env-down      # Stop environment
make test-env-clean     # Full cleanup
```

**What it tests:**
- Contract deployment to Anvil
- Event generation (140+ deterministic events)
- Indexer scanning and storage
- API search and filtering
- Pagination
- Error handling
- End-to-end data flow

**Environment:**
- Anvil (port 8545): Local Ethereum node
- Postgres (port 5434): Test database
- Valkey (port 6380): Test cache
- Indexer API (port 8081): Service under test

### 3. E2E Tests (Live Service)

Tests against a running eth-indexer instance (external setup required).

```bash
cd test

# All tests
npm test

# Specific suites
npm run test:health
npm run test:search
npm run test:filters
npm run test:errors
npm run test:performance
```

**What it tests:**
- Health endpoints
- Search functionality
- Filter combinations
- Error responses
- Performance under load

**Prerequisites:**
- eth-indexer running on `http://localhost:8080`
- Service must have indexed events

## Integration Test Details

### Architecture

```
┌─────────────────────────────────────────────┐
│ Docker Compose (docker-compose.test.yml)    │
├─────────────────────────────────────────────┤
│                                              │
│  1. Anvil (Foundry)                         │
│     - Deterministic mnemonic                │
│     - 1s block time                         │
│     - Chain ID: 31337                       │
│         ↓                                    │
│  2. Contract Deployer (one-shot)            │
│     - Deploys 2 TestTokens                  │
│     - Generates 140 events                  │
│     - Saves addresses to JSON               │
│         ↓                                    │
│  3. eth-indexer                             │
│     - Scans Anvil chain                     │
│     - Stores in Postgres                    │
│     - Caches in Valkey                      │
│     - Exposes API on :8081                  │
│         ↓                                    │
│  4. Jest Integration Tests                  │
│     - Validates all indexed events          │
│     - Tests search/filter/pagination        │
│     - Verifies deterministic data           │
│                                              │
└─────────────────────────────────────────────┘
```

### Test Data

**Contracts:**
- Token1 (TUSDC): Simple ERC20-like token
- Token2 (TUSDT): Simple ERC20-like token

**Events Generated:**
- Token1: 50 Transfer + 30 Approval = 80 events
- Token2: 40 Transfer + 20 Approval = 60 events
- Constructor: 2 Transfer events (minting)
- **Total: 142 events**

**Deterministic Addresses:**
```
Deployer:  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
Alice:     0x1111111111111111111111111111111111111111
Bob:       0x2222222222222222222222222222222222222222
Charlie:   0x3333333333333333333333333333333333333333
```

### Test Coverage

**integration/e2e.test.js:**
- ✓ Health check returns healthy status
- ✓ All 92+ Transfer events indexed (90 regular + 2 constructor)
- ✓ All 50 Approval events indexed
- ✓ Total 142+ events indexed
- ✓ Filter by Token1 address (50+ Transfers)
- ✓ Filter by Token2 address (40+ Transfers)
- ✓ Transfer events have deterministic recipients
- ✓ Transfer values are deterministic
- ✓ Pagination with limit works
- ✓ search_after pagination works
- ✓ Invalid event name returns error
- ✓ Invalid contract address returns empty results

## Verification Commands

### Manual Testing

```bash
# Start test environment
make test-env-up

# Verify Anvil
cast client --rpc-url http://localhost:8545
cast block-number --rpc-url http://localhost:8545

# Check deployed contracts
cat deployed-addresses.json

# Verify indexer health
curl http://localhost:8081/health

# Query events
curl http://localhost:8081/search/Transfer | jq '.total'
# Expected: 92+

curl http://localhost:8081/search/Approval | jq '.total'
# Expected: 50

# Filter by contract
TOKEN1=$(jq -r '.token1' deployed-addresses.json)
curl "http://localhost:8081/search/Transfer?contractAddress=${TOKEN1}" | jq '.total'
# Expected: 51 (50 + 1 constructor)

# View logs
docker-compose -f docker-compose.test.yml logs -f indexer

# Cleanup
make test-env-down
```

## Continuous Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.23'

      - name: Run unit tests
        run: make test-unit

      - name: Install Foundry
        uses: foundry-rs/foundry-toolchain@v1

      - name: Run integration tests
        run: make test-e2e
```

## Performance Benchmarks

Expected performance for integration tests:

- **Environment startup**: ~30 seconds
  - Anvil: 2s
  - Contract deployment: 5s
  - Event generation: 10s
  - Indexer sync: 10-15s

- **Test execution**: ~10-20 seconds
  - 12 test cases
  - 140+ events validated

- **Teardown**: ~5 seconds

**Total E2E runtime: ~45-60 seconds**

## Troubleshooting

### Integration Tests

**Error: deployed-addresses.json not found**
```bash
# Check contract deployer logs
docker-compose -f docker-compose.test.yml logs contract-deployer

# Manually run deployment
docker-compose -f docker-compose.test.yml up contract-deployer
```

**Error: Indexer not syncing**
```bash
# Check indexer logs
docker-compose -f docker-compose.test.yml logs -f indexer

# Verify Anvil is accessible from indexer container
docker-compose -f docker-compose.test.yml exec indexer \
  curl http://anvil:8545 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**Error: Port already in use**
```bash
# Check what's using the ports
lsof -i :8545  # Anvil
lsof -i :8081  # Indexer API
lsof -i :5434  # Postgres
lsof -i :6380  # Valkey

# Stop conflicting services
make test-env-clean
```

**Error: Tests timeout**
```bash
# Increase Jest timeout in test/integration/e2e.test.js
# Check if indexer is under load
docker stats

# Verify indexer is processing blocks
curl http://localhost:8081/health
```

### E2E Tests (Live Service)

**Error: Connection refused**
```bash
# Verify service is running
curl http://localhost:8080/health

# Check service logs
docker-compose logs -f indexer

# Verify correct port
echo $API_BASE_URL  # Should be http://localhost:8080
```

**Error: No events found**
```bash
# Check indexer status
curl http://localhost:8080/status

# Verify events exist
curl http://localhost:8080/search/Transfer | jq '.total'

# Check if indexer is syncing
# Wait a few minutes, then retry
```

## Development Workflow

### Adding New Tests

**1. Integration tests (test/integration/):**
```javascript
// test/integration/new-feature.test.js
const { getIndexerHealth, searchEvents } = require('./setup');

describe('New Feature', () => {
  test('should do something', async () => {
    const result = await searchEvents('Transfer', {});
    expect(result.hits.length).toBeGreaterThan(0);
  });
});
```

**2. E2E tests (test/e2e/):**
```javascript
// test/e2e/new-feature.test.js
const axios = require('axios');
const { API_BASE_URL } = require('./setup');

describe('New Feature', () => {
  test('should do something', async () => {
    const response = await axios.get(`${API_BASE_URL}/new-endpoint`);
    expect(response.status).toBe(200);
  });
});
```

### Updating Test Contracts

```bash
# Edit contracts
vim test/contracts/src/TestToken.sol

# Rebuild
make contracts-build

# Test contracts
make contracts-test

# Test integration
make test-e2e
```

## Best Practices

1. **Run unit tests frequently** - Fast feedback during development
2. **Run integration tests before commits** - Catch integration issues early
3. **Use test-env-up for debugging** - Keep environment running while developing
4. **Clean up after testing** - Use test-env-clean to avoid state issues
5. **Check logs when tests fail** - docker-compose logs provides detailed info
6. **Use deterministic test data** - Integration tests should be reproducible
7. **Keep tests independent** - Each test should work in isolation

## Resources

- **Test directory**: `/test/README.md`
- **Contract docs**: `/test/contracts/README.md`
- **Makefile targets**: `make help`
- **Docker Compose**: `docker-compose.test.yml`
- **Jest config**: `test/jest.config.js`
