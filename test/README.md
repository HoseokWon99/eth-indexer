# eth-indexer API Tests

Comprehensive JavaScript test suite for the eth-indexer API using Jest.

## Setup

### Install Dependencies

```bash
cd test
npm install
```

## Running Tests

### Run All Tests

```bash
npm test
```

### Run Specific Test Suites

```bash
# Health and status tests
npm run test:health

# Search endpoint tests
npm run test:search

# Filter tests
npm run test:filters

# Error handling tests
npm run test:errors

# Performance tests
npm run test:performance
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
├── package.json          # Dependencies and scripts
├── jest.config.js        # Jest configuration
├── setup.js              # Global test setup and utilities
├── health.test.js        # Health and status endpoint tests
├── search.test.js        # Search endpoint tests
├── filters.test.js       # Filter parameter tests
├── errors.test.js        # Error handling tests
└── performance.test.js   # Performance and load tests
```

## Test Suites

### 1. Health Tests (`health.test.js`)

Tests for health and status endpoints:
- Health endpoint returns 200 OK
- Status endpoint returns valid JSON
- Block numbers are numeric and non-negative
- Block numbers update over time

### 2. Search Tests (`search.test.js`)

Tests for search endpoints:
- Response format (count + result)
- Event structure validation
- Data field validation (Transfer: from/to/value, Approval: owner/spender/value)
- Ethereum address format validation
- Transaction and block hash validation
- Timestamp format validation

### 3. Filter Tests (`filters.test.js`)

Tests for all filter types:
- **Contract Address**: Single and multiple addresses
- **Block Number**: gte, lte, gt, lt, eq, ranges
- **Transaction Hash**: Exact match
- **Block Hash**: Exact match
- **Log Index**: Single and multiple values
- **Combined Filters**: Multiple filters together

### 4. Error Tests (`errors.test.js`)

Tests for error handling:
- Invalid topics (404)
- Invalid filter parameters (400)
- Invalid endpoints (404)
- HTTP method validation (405 for POST/PUT/DELETE)
- Edge cases (large values, empty params, case sensitivity)

### 5. Performance Tests (`performance.test.js`)

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

## Prerequisites

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
