# E2E Test Plan

Implement this under `test/e2e/`

## Goals
1. Verify whether all published events indexed
2. Verify search api works
3. Verify /indexer/status endpoint

## Steps

### Common Step (Should be executed before all)
1. Deploy Smart Contract (If not deployed)
2. Generate Events

These are handled by `make test-env-up` via `scripts/test/setup-test-env.sh`.

---

## Prerequisites / Infrastructure Fixes

### 1. Fix port conflict in `docker-compose.test.yml`
Both indexer and api-server currently bind to external port 8081:
- Indexer: `"8081:8080"` → keep (external **8081**)
- API server: `"8081:8081"` → change to `"8082:8081"` (external **8082**)

### 2. Update `scripts/test/setup-test-env.sh`
Add api-server startup and health wait after the indexer step:
```bash
docker-compose -f "${PROJECT_ROOT}/docker-compose.test.yml" up -d api-server
# wait until /health returns 200
```

---

## Test Infrastructure

### Framework
- **Jest** (Node.js) — `cd test && npm test`
- Direct **PostgreSQL** queries via `pg` package for DB assertions

### Files to Create

| File | Purpose |
|------|---------|
| `test/package.json` | Jest + pg dependencies |
| `test/jest.config.js` | `testMatch: ['**/e2e/**/*.test.js']`, timeout 60s |
| `test/e2e/setup.js` | Shared constants, `pg.Pool`, API fetch helpers, retry util |
| `test/e2e/indexing.test.js` | Goal 1 |
| `test/e2e/search.test.js` | Goal 2 |
| `test/e2e/status.test.js` | Goal 3 |

### `test/e2e/setup.js` exports
- `DB_CONFIG` — `{ host: 'localhost', port: 5434, database: 'eth_indexer_test', user: 'indexer', password: 'indexer_password' }` (overridable via env vars)
- `API_BASE_URL` — `process.env.API_BASE_URL || 'http://localhost:8082'`
- `INDEXER_BASE_URL` — `process.env.INDEXER_BASE_URL || 'http://localhost:8081'`
- `apiGet(path, params)` — fetch wrapper returning parsed JSON
- `BROADCAST_PATH` — absolute path to `test/contracts/broadcast/GenerateEvents.s.sol/31337/run-latest.json`

---

## Goal 1 — `test/e2e/indexing.test.js`

Verify every transaction in the broadcast file has a corresponding `event_records` row.

### Steps
1. Load `run-latest.json`, partition transactions by function name:
   - `transfer(address,uint256)` → expected Transfer events (120 tx)
   - `approve(address,uint256)` → expected Approval events (120 tx)
2. Query PostgreSQL: `SELECT * FROM event_records`
3. Compare

### Test Cases
- `all Transfer tx hashes are indexed` — every transfer tx hash from broadcast exists in DB with `topic = 'Transfer'`
- `all Approval tx hashes are indexed` — every approve tx hash from broadcast exists in DB with `topic = 'Approval'`
- `Transfer count in DB >= broadcast count` — constructor Transfers (2) inflate DB count, so DB >= 120
- `Approval count in DB == broadcast count` — exactly 120

---

## Goal 2 — `test/e2e/search.test.js`

Verify `GET /search/{topic}` on API server (port 8082) using various filters.
Cross-check results against direct DB queries for correctness.

### Steps
1. SELECT all event_records from PostgreSQL (reference dataset)
2. Send requests with each filter type and verify result matches reference

### Test Cases

**Response shape**
- `GET /search/Transfer` returns `{ count: N, result: [...] }`
- Each record has: `contract_address`, `tx_hash`, `block_hash`, `block_number`, `log_index`, `data`, `timestamp`
- Transfer `data` has `from`, `to`, `value`; Approval `data` has `owner`, `spender`, `value`
- Unknown topic `GET /search/Foo` returns 404

**Filters**
- `contract_address=<token1>` — all results have that contract address
- `block_number={"gte":N}` — all results have block_number >= N
- `block_number={"lte":N}` — all results have block_number <= N
- `block_number={"gte":A,"lte":B}` — results in range
- `tx_hash=<hash>` — matches specific transaction from broadcast
- `log_index=0,1` — results have log_index in [0,1]
- `data={"to":"0x1111..."}` — JSONB containment filter on Transfer data
- Combined: `contract_address` + `block_number` range

**Pagination**
- `limit=5` — response count <= 5
- `cursor` pagination: page 1 + page 2 are disjoint and together equal ungpaginated result

---

## Goal 3 — `test/e2e/status.test.js`

Verify `GET /state` on indexer service (port 8081).

### Steps
1. GET `http://localhost:8081/state`
2. Parse JSON response
3. Assert structure and values

### Test Cases
- Returns 200 with JSON body
- Response object has `Transfer` key with non-negative integer value
- Response object has `Approval` key with non-negative integer value
- Both block numbers are > 0 (indexer has processed blocks)
- `GET /health` returns 200

---

## Test Data Reference

**Expected event counts (from `GenerateEvents.s.sol`):**
- 60 loop iterations × 2 tokens = 120 Transfer events
- 60 loop iterations × 2 tokens = 120 Approval events
- +2 constructor Transfers (from Deploy.s.sol) = **242 total in DB**

**Deterministic addresses (Anvil default mnemonic):**
- Token1: `0x5FbDB2315678afecb367f032d93F642f64180aa3`
- Token2: `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512`
- Alice (account 1): `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`
- Bob (account 2): `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC`
- Charlie (account 3): `0x90F79bf6EB2c4f870365E785982E1f101E93b906`

---

## Verification

```bash
make test-env-clean   # clean previous state
make test-env-up      # start all services + deploy + generate events
make test-integration # cd test && npm test
make test-env-down    # cleanup
# Or full cycle:
make test-e2e
```
