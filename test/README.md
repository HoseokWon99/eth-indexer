# eth-indexer Tests

Comprehensive test suite for eth-indexer including E2E tests with live service and integration tests with Anvil local blockchain.

## Setup

### Install Dependencies

```bash
cd test
npm install
```

## Test Types

### 1. Integration Tests (Anvil)

Full-stack tests with local Ethereum blockchain (Anvil), deterministic test data, and isolated environment.

```bash
# Run full E2E test cycle (setup -> test -> teardown)
make test-e2e

# Or run steps manually:
make test-env-up        # Start Anvil + deploy contracts + start indexer
npm run test:integration # Run integration tests
make test-env-down      # Stop environment

# Clean up everything
make test-env-clean
```

**What it tests:**
- Contract deployment and event indexing
- All 140+ test events indexed correctly
- Search and filter functionality
- Pagination (limit, search_after)
- Error handling
- Deterministic, reproducible results

### 2. E2E Tests (Live Service)

Tests against running eth-indexer service (requires external setup).

```bash
# Run E2E tests
npm test

# Run specific test suites
npm run test:health      # Health and status tests
npm run test:search      # Search endpoint tests
npm run test:filters     # Filter parameter tests
npm run test:errors      # Error handling tests
npm run test:performance # Performance tests
```

### Run Tests in Watch Mode

```bash
npm run test:watch
```

### Generate Coverage Report

```bash
npm run test:coverage
```

## Test Structure

```
test/
├── contracts/            # Solidity test contracts (see contracts/README.md)
│   ├── src/              # TestToken.sol
│   ├── script/           # Deploy and event generation scripts
│   └── foundry.toml      # Foundry configuration
├── e2e/                  # E2E tests for live service
│   ├── setup.js          # Test utilities
│   ├── health.test.js    # Health and status tests
│   ├── search.test.js    # Search endpoint tests
│   ├── filters.test.js   # Filter parameter tests
│   ├── errors.test.js    # Error handling tests
│   └── performance.test.js # Performance tests
├── integration/          # Integration tests with Anvil
│   ├── setup.js          # Anvil utilities (RPC, sync helpers)
│   └── e2e.test.js       # Full integration test suite
├── package.json          # Dependencies and scripts
└── jest.config.js        # Jest configuration
```

## Integration Test Environment (Anvil)

The integration test environment provides:

- **Deterministic blockchain**: Same state on every run
- **Fast feedback**: Local node, no network latency
- **Isolated**: No conflicts with production data
- **Complete control**: Generate specific test scenarios

### Architecture

```
┌─────────────────────────────────────────────────────┐
│ Docker Compose Test Environment                     │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Anvil (port 8545)        Postgres (port 5434)     │
│    ↓                           ↓                    │
│  Deploy Contracts →        Valkey (port 6380)       │
│  Generate Events               ↓                    │
│    ↓                           ↓                    │
│  eth-indexer (port 8081)  ←────┘                   │
│    ↓                                                │
│  Jest Integration Tests                             │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### Test Data

- **Token1 (TUSDC)**: 50 Transfers + 30 Approvals = 80 events
- **Token2 (TUSDT)**: 40 Transfers + 20 Approvals = 60 events
- **Total**: 140 events + 2 constructor events = 142 events

Deterministic addresses:
- Deployer: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- Alice: `0x1111111111111111111111111111111111111111`
- Bob: `0x2222222222222222222222222222222222222222`
- Charlie: `0x3333333333333333333333333333333333333333`

### Verification

```bash
# Check Anvil is running
cast client --rpc-url http://localhost:8545

# Check indexer health
curl http://localhost:8081/health

# Query indexed events
curl http://localhost:8081/search/Transfer | jq '.total'
# Should return 92+ (90 regular + 2 constructor)

curl http://localhost:8081/search/Approval | jq '.total'
# Should return 50
```

## E2E Test Suites

### 1. Health Tests (`e2e/health.test.js`)

Tests for health and status endpoints:
- Health endpoint returns 200 OK
- Status endpoint returns valid JSON
- Block numbers are numeric and non-negative
- Block numbers update over time

### 2. Search Tests (`e2e/search.test.js`)

Tests for search endpoints:
- Response format (count + result)
- Event structure validation
- Data field validation (Transfer: from/to/value, Approval: owner/spender/value)
- Ethereum address format validation
- Transaction and block hash validation
- Timestamp format validation

### 3. Filter Tests (`e2e/filters.test.js`)

Tests for all filter types:
- **Contract Address**: Single and multiple addresses
- **Block Number**: gte, lte, gt, lt, eq, ranges
- **Transaction Hash**: Exact match
- **Block Hash**: Exact match
- **Log Index**: Single and multiple values
- **Combined Filters**: Multiple filters together

### 4. Error Tests (`e2e/errors.test.js`)

Tests for error handling:
- Invalid topics (404)
- Invalid filter parameters (400)
- Invalid endpoints (404)
- HTTP method validation (405 for POST/PUT/DELETE)
- Edge cases (large values, empty params, case sensitivity)

### 5. Performance Tests (`e2e/performance.test.js`)

Tests for performance:
- Response time benchmarks
- Concurrent request handling
- Large result set handling
- Response time consistency
- API availability under load
- Memory/resource usage

## Environment Variables

```bash
# Set custom API URL (default: http://localhost:8080)
export API_BASE_URL=http://localhost:8080

# Run tests
npm test
```

## Test Output

### Success Example

```
PASS  ./health.test.js
  Health and Status Endpoints
    GET /health
      ✓ should return 200 OK (15 ms)
      ✓ should return "OK" text (3 ms)
    GET /status
      ✓ should return 200 OK (4 ms)
      ✓ should have Transfer and Approval properties (2 ms)

Test Suites: 5 passed, 5 total
Tests:       78 passed, 78 total
Snapshots:   0 total
Time:        15.234 s
```

## Coverage Report

After running `npm run test:coverage`, view the report:

```bash
open coverage/lcov-report/index.html
```

## Integration Test Suites

### Event Indexing Tests (`integration/e2e.test.js`)

Tests for Anvil-based integration:
- All 140+ events indexed
- Event structure validation
- Contract address filtering
- Deterministic event data
- Pagination (limit, search_after)
- Error handling

## Prerequisites

### For Integration Tests (Anvil)
- Docker and Docker Compose
- Foundry (forge, cast, anvil)
- Node.js 16+
- Make

### For E2E Tests (Live Service)
- Node.js 16+ recommended
- eth-indexer service running on http://localhost:8080
- Service should have some indexed events for full test coverage

## Continuous Integration

These tests can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Install test dependencies
  run: cd test && npm install

- name: Run API tests
  run: cd test && npm test
  env:
    API_BASE_URL: http://localhost:8080
```

## Troubleshooting

### Connection Refused

If tests fail with connection errors:
1. Ensure eth-indexer service is running
2. Check the service is accessible at http://localhost:8080
3. Verify with: `curl http://localhost:8080/health`

### Tests Failing Due to No Data

Some tests require indexed events. If you see "Skip if no sample data":
1. Wait for the indexer to process some blocks
2. Verify events exist: `curl http://localhost:8080/search/Transfer`
3. Check indexer status: `curl http://localhost:8080/status`

### Timeout Errors

If tests timeout:
1. Increase Jest timeout in `jest.config.js` (default: 30000ms)
2. Check if the indexer is under heavy load
3. Verify database connection is stable

## Contributing

When adding new tests:
1. Follow the existing test structure
2. Use descriptive test names
3. Group related tests in `describe` blocks
4. Add assertions for both success and failure cases
5. Update this README if adding new test files
