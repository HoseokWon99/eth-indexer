# Integration Test Plan

## Current State

- **Zero Go tests exist** anywhere in the repo (`*_test.go` files: none)
- Existing tests are Jest/Node.js E2E only via `docker-compose.test.yml`
- `test/postgres/` and `test/kafka/` compose fixtures exist but aren't wired to any Go tests

## Three-Layer Architecture

| Layer | Tool | Infra |
|---|---|---|
| Unit tests | mocks / `SimulatedBackend` | none |
| Integration tests | real containers | Postgres, Valkey, Kafka |
| E2E (existing) | Jest + Docker Compose | full stack |

---

## Phase 1 — No infrastructure (unit tests)

| File | Coverage |
|---|---|
| ~~`libs/config/postgres_test.go`~~ | ~~env parsing~~ (skipped) |
| `services/indexer/scanner/scanner_test.go` | ABI decode with `SimulatedBackend` |
| `services/indexer/core/indexer_test.go` | block range calc, `confirmedAfter`, concurrency |
| `services/indexer/storage/state_storage_test.go` | JSON file I/O with `t.TempDir()` |
| `services/api-server/api/handlers_test.go` | HTTP handler (cache hit/miss/error) via `httptest` |
| `services/api-server/api/handlers_parse_test.go` | query string parsing |

### `scanner_test.go` — test cases

Use `go-ethereum/accounts/abi/backends.SimulatedBackend` (in-process, no Docker).

| Test | Scenario |
|---|---|
| `TestScan_EmptyRange` | `fromBlock >= toBlock` returns nil slice |
| `TestScan_FiltersCorrectTopic0` | Two events deployed; scanner for Topic A does not return Topic B logs |
| `TestScan_DecodesIndexedFields` | Indexed ERC20 `from`/`to` addresses land in `data` map with correct keys |
| `TestScan_DecodesNonIndexedFields` | Non-indexed `value` is ABI-decoded from `log.Data` |
| `TestScan_SortsByBlockNumber` | Logs from multiple blocks returned sorted ascending |
| `TestScan_MultipleContractAddresses` | Two contracts; scanner includes both |
| `TestScan_MalformedLogSkipped` | Log with wrong topic0 is skipped, not an error |
| `TestScan_UnknownEventName` | `NewEventRecordsScanner` with event name absent from ABI returns error |
| `TestScan_SetsLogIndex` | `EventRecord.LogIndex` matches `lg.Index` (verifies known bug) |
| `TestScan_DeterministicTimestamp` | Documents that timestamp currently uses wall clock, not block timestamp (known bug) |

### `indexer_test.go` — test cases

Use mock implementations of `Scanner`, `EventRecordsStorage`, `StateStorage`.

| Test | Scenario |
|---|---|
| `TestIndexAll_CallsScanWithCorrectRange` | `lastBlock=5`, `latestBlock=10`, `confirmedAfter=2` → Scan called with `(6, 8)` |
| `TestIndexAll_SkipsWhenFromGeqTo` | `lastBlock >= latestBlock - confirmedAfter` → no scan, no save |
| `TestIndexAll_SavesLastBlockFromLastRecord` | After scanning blocks 6-8, `SetLastBlockNumber` called with block of last record |
| `TestIndexAll_ConcurrentScanners` | Two scanners run concurrently; both complete; both states updated |
| `TestIndexAll_StorageErrorDoesNotPanic` | `SaveAll` returns error → logs but does not crash |
| `TestIndexAll_ScannerErrorDoesNotPanic` | `Scan` returns error → logged, state not updated |
| `TestClose_SavesState` | After `Close()`, `stateStorage.Save()` has been called |

### `state_storage_test.go` — test cases

Use `t.TempDir()` for isolated file I/O, no Docker.

| Test | Scenario |
|---|---|
| `TestNewSimpleStateStorage_CreatesFile` | File does not exist → creates empty `{}` file |
| `TestNewSimpleStateStorage_ReadsExistingState` | File has `{"Transfer": 100}` → loads 100 for Transfer |
| `TestNewSimpleStateStorage_UsesOffsetForNewEvent` | File has no entry for "Approval" → initializes to `offsetBlockNumber` |
| `TestSetLastBlockNumber_UnknownEvent` | Returns error for unknown event name |
| `TestSave_WritesToDisk` | After `SetLastBlockNumber`, `Save()` writes updated JSON to file |

### `handlers_test.go` — test cases

Use `net/http/httptest`, mock `EventRecordsStorage` and `CacheStorage`.

| Test | Scenario |
|---|---|
| `TestHealth_Returns200` | `GET /health` returns 200 with body "OK" |
| `TestSearch_UnknownTopic_404` | `GET /search/Unknown` returns 404 |
| `TestSearch_NonGetMethod_405` | `POST /search/Transfer` returns 405 |
| `TestSearch_CacheHit_SkipsStorage` | Cache returns a result; storage `FindAll` is never called |
| `TestSearch_CacheMiss_QueriesStorage` | Cache returns expired=true; storage `FindAll` called; result written to cache |
| `TestSearch_StorageError_500` | Storage returns error; handler returns 500 |
| `TestSearch_CacheWriteError_StillReturns200` | Cache `Set` fails; response still sent correctly |
| `TestSearch_ResponseEncoding` | JSON body matches `SearchResponse{Count: N, Result: [...]}` |

### `handlers_parse_test.go` — test cases

Table-driven tests for query string parsing functions.

| Test | Scenario |
|---|---|
| `TestExtractFilters_ContractAddress` | `contract_address=0xABC,0xDEF` → `[]string{"0xABC","0xDEF"}` |
| `TestExtractFilters_BlockNumber_Comparison` | `block_number={"gte":10,"lte":20}` → filter with both operators |
| `TestExtractFilters_InvalidBlockNumber` | Non-JSON value → returns error |
| `TestExtractFilters_LogIndex` | `log_index=0,1,2` → `[]uint64{0,1,2}` |
| `TestExtractFilters_InvalidLogIndex` | `log_index=abc` → returns error |
| `TestExtractFilters_DataJSONB` | `data={"from":"0x..."}` → populates `Data` map |
| `TestExtractPaging_Cursor` | `cursor={"block_number":5,"log_index":3}` → populated cursor |
| `TestExtractPaging_Limit` | `limit=50` → `PagingOptions.Limit == 50` |
| `TestExtractPaging_InvalidLimit` | `limit=abc` → returns error |

---

## Phase 2 — Postgres/Valkey integration (`//go:build integration`)

| File | Coverage |
|---|---|
| `services/indexer/storage/event_records_storage_test.go` | bulk insert, idempotency (`ON CONFLICT`) |
| `services/api-server/storage/event_records_storage_test.go` | all filter/pagination SQL — **highest priority** |
| `services/api-server/storage/cache_storage_test.go` | Redis TTL, cache miss/hit |

### `indexer/storage/event_records_storage_test.go` — test cases

Requires Postgres. Call `storage.Migrate(pool)` before tests, truncate between cases.

| Test | Scenario |
|---|---|
| `TestSaveAll_PersistsRecords` | Insert 3 records; direct SQL query returns all 3 with correct fields |
| `TestSaveAll_Idempotent` | Insert same `(tx_hash, log_index)` twice; only 1 row in DB |
| `TestSaveAll_MultipleTopic` | Insert Transfer and Approval records; stored with correct `topic` column |
| `TestSaveAll_LargeBatch` | Insert 500 records in one batch; verify count |
| `TestSaveAll_JSONBData` | JSONB `data` round-trips correctly for string, address, and `*big.Int`-encoded values |

### `api-server/storage/event_records_storage_test.go` — test cases

Highest priority. Will catch the `appendGin` JSONB bug immediately.

| Test | Scenario |
|---|---|
| `TestFindAll_ByTopic` | Only records matching topic are returned |
| `TestFindAll_ByContractAddress_Single` | Filters to one contract |
| `TestFindAll_ByContractAddress_Multi` | Two addresses → both contracts' records returned |
| `TestFindAll_ByTxHash` | Exact match on tx_hash |
| `TestFindAll_ByBlockHash` | Exact match on block_hash |
| `TestFindAll_BlockNumber_GTE` | Only blocks ≥ N returned |
| `TestFindAll_BlockNumber_LTE` | Only blocks ≤ N returned |
| `TestFindAll_BlockNumber_Range` | GTE and LTE combined |
| `TestFindAll_BlockNumber_EQ` | Exact block match |
| `TestFindAll_LogIndex_Single` | Exact log_index match |
| `TestFindAll_LogIndex_Multi` | Multiple log indices (IN clause) |
| `TestFindAll_JSONB_Data` | `data={"from":"0xABC"}` returns only matching records |
| `TestFindAll_Timestamp_Comparison` | Timestamp GTE/LTE filtering |
| `TestFindAll_Pagination_Limit` | `limit=10` → 10 records max |
| `TestFindAll_Pagination_Cursor` | Cursor at `(block_number=5, log_index=2)` → only records after it |
| `TestFindAll_Pagination_CursorNextPage` | Full page-through: first page ends at cursor X; next page starts from X |
| `TestFindAll_Empty` | No matching records returns empty slice, not nil |
| `TestFindAll_OrderingIsConsistent` | Results always ordered `(block_number ASC, log_index ASC)` |

### `api-server/storage/cache_storage_test.go` — test cases

Requires Valkey/Redis.

| Test | Scenario |
|---|---|
| `TestGet_CacheMiss_ReturnsExpired` | Key not in Redis → `(SearchResponse{}, expired=true, nil)` |
| `TestSet_Then_Get_CacheHit` | Set a value, Get it → `(value, expired=false, nil)` |
| `TestSet_TTL_Expiry` | Set with TTL=1s; sleep 2s; Get returns expired=true |
| `TestGet_CorruptJSON_ReturnsError` | Manually set non-JSON string under prefix key → Get returns error |
| `TestSet_LargePayload` | Payload with 1000 records round-trips correctly |

---

## Phase 3 — Kafka integration

Requires extracting dashboard routing into a `router` package first.

### Prerequisite refactor

Extract `services/dashboard/main.go` routing loop into:

```
services/dashboard/router/router.go
  type Config struct {
      Brokers     []string
      SourceTopic string
      DestPrefix  string
  }
  func Run(ctx context.Context, cfg Config) error
```

### `services/dashboard/router/router_test.go` — test cases

| Test | Scenario |
|---|---|
| `TestRouter_TransferEventRoutedCorrectly` | Publish Debezium message with `topic: "Transfer"` → consumer on `eth-indexer.events.Transfer` receives it |
| `TestRouter_ApprovalEventRoutedCorrectly` | Same for Approval |
| `TestRouter_UnknownTopicRoutedToUnknown` | Message missing `topic` field → routed to `eth-indexer.events.unknown` |
| `TestRouter_MalformedJSONSkippedAndCommitted` | Non-JSON message → commit called; no write to destination; no hang |
| `TestRouter_MultipleEventTypes` | 100 messages across 3 event types → each destination topic has correct count |
| `TestRouter_OffsetCommittedAfterWrite` | Restart consumer mid-stream; no duplicate messages |
| `TestRouter_GracefulShutdown` | Cancel context; consumer exits cleanly; all inflight messages committed |

---

## Infra Setup Strategy

**Primary (CI):** `testcontainers-go` — each `TestMain` starts/stops containers inline. Self-contained, no prerequisite `docker compose up`.

**Fallback (local dev):** Use existing compose stacks with `INTEGRATION_USE_COMPOSE=true` env var to skip container startup.

Both approaches coexist: integration tests detect `INTEGRATION_USE_COMPOSE=true` and skip container startup accordingly.

---

## Known Bugs These Tests Will Catch

1. **`appendGin` JSONB bug** (`api-server/storage/event_records_storage.go:134`)
   - `sq.Expr("? @> '?'", column, raw)` renders the second `?` literally instead of substituting
   - Fix: `sq.Expr(column+" @> ?", string(raw))`
   - Caught by: `TestFindAll_JSONB_Data`

2. **`Timestamp` uses wall clock** (`indexer/scanner/scanner.go`)
   - `time.Now()` instead of block timestamp → non-deterministic across replays
   - Caught by: `TestScan_DeterministicTimestamp`

3. **`LogIndex` never set** in `parseLog`
   - `EventRecord.LogIndex` always 0 because `lg.Index` is not assigned
   - Caught by: `TestScan_SetsLogIndex`

---

## Makefile Targets

```makefile
test-unit-go:
    cd services/indexer && go test ./...
    cd services/api-server && go test ./...

test-integration-go: compose-infra-up
    cd services/api-server && go test -tags integration ./...
    cd services/indexer && go test -tags integration ./...
    cd services/dashboard && go test -tags integration ./...
    $(MAKE) compose-infra-down
```