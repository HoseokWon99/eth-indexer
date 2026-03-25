# Plan: Monorepo with `go.work` — Split into Microservices

## Goal
Restructure `eth-indexer` into a Go workspace monorepo using `go.work`, splitting the monolith into three independent services. Shared lib stays thin (types + interfaces only); implementations live in the service that uses them.

- **indexer**: headless Ethereum event indexer (RPC → PostgreSQL)
- **api-server**: stateless HTTP search API (PostgreSQL + Redis → HTTP)
- **dashboard**: CDC event router (Kafka topic fan-out)

```
Client <-> api-server (N) <-> PostgreSQL/Redis <-> indexer
                                    |
                              dashboard <-> Kafka
```

## Interface Split: EventRecordsStorage

Current single interface:
```go
type EventRecordsStorage interface {
    SaveAll(ctx context.Context, topic string, records []EventRecord) error
    FindAll(ctx context.Context, topic string, filters EventRecordFilters) ([]EventRecord, error)
}
```

Split into two:
```go
// EventRecordWriter — used by indexer only
type EventRecordWriter interface {
    SaveAll(ctx context.Context, topic string, records []EventRecord) error
}

// EventRecordReader — used by api-server only
type EventRecordReader interface {
    FindAll(ctx context.Context, topic string, filters EventRecordFilters) ([]EventRecord, error)
}
```

Each service implements only the half it needs against PostgreSQL directly.

## Target Directory Structure

```
eth-indexer/
├── go.work                          # workspace: use libs/common, services/*
│
├── libs/
│   └── common/                      # shared module: eth-indexer/libs/common
│       ├── go.mod                   # minimal deps (no go-ethereum, no squirrel, no redis)
│       ├── go.sum
│       └── types.go                 # EventRecord, EventRecordFilters, ComparisonFilter/Op
│                                    # EventRecordWriter interface
│                                    # EventRecordReader interface
│
├── services/
│   ├── indexer/                     # module: eth-indexer/services/indexer
│   │   ├── go.mod                   # requires eth-indexer/libs/common, go-ethereum, pgx
│   │   ├── go.sum
│   │   ├── main.go                  # entrypoint
│   │   ├── config.go                # IndexerConfig (RPC, ABI, events, confirmedAfter, postgres)
│   │   ├── service.go               # IndexerService (from service/indexer_service.go)
│   │   ├── worker.go                # Worker (from core/worker.go)
│   │   ├── scanner.go               # Scanner interface + EventRecordsScanner impl (from core/scanner.go + scanner/scanner.go)
│   │   ├── storage.go               # PostgresEventRecordWriter — SaveAll only (from storage/event_records_storage.go)
│   │   ├── state.go                 # StateStorage interface + SimpleStateStorage impl (from core/state.go + storage/state_storage.go)
│   │   ├── state_test.go            # (from storage/state_storage_test.go)
│   │   └── Dockerfile
│   │
│   ├── api-server/                  # module: eth-indexer/services/api-server
│   │   ├── go.mod                   # requires eth-indexer/libs/common, pgx, squirrel, redis
│   │   ├── go.sum
│   │   ├── main.go                  # entrypoint: PG + Redis + SearchService + HTTP
│   │   ├── config.go                # SearchConfig (API port, TTL, postgres, redis, topics)
│   │   ├── service.go               # SearchService (from service/search_service.go)
│   │   ├── storage.go               # PostgresEventRecordReader — FindAll only (from storage/event_records_storage.go)
│   │   ├── cache.go                 # CacheStorage interface + RedisCacheStorage impl (from core/cache.go + storage/cache_storage.go)
│   │   ├── handlers.go              # HTTP handlers (from api/handlers.go, no IndexerService dep)
│   │   ├── server.go                # HTTP server (from api/server.go, no /status route)
│   │   ├── schema.go                # request/response types (from api/schema.go)
│   │   └── Dockerfile
│   │
│   └── dashboard/                # module: eth-indexer/services/dashboard
│       ├── go.mod                   # standalone (only kafka-go + stdlib)
│       ├── go.sum
│       ├── main.go                  # existing dashboard logic
│       └── Dockerfile
│
├── migrations/                      # shared SQL migrations
├── monitoring/                      # shared dashboards/alerts
├── test/                            # integration tests
├── docker-compose.yml               # all services
├── Makefile                         # build/run targets per service
└── README.md
```

## What lives where

### `libs/common` — types and interfaces only (no implementations)
- `EventRecord` struct
- `EventRecordFilters`, `ComparisonFilter[T]`, `ComparisonOp` types
- `EventRecordWriter` interface (`SaveAll`)
- `EventRecordReader` interface (`FindAll`)
- No external deps beyond stdlib

### `services/indexer` — all indexing implementation
- `Worker` — block range calculation + scan + save (from `core/worker.go`)
- `Scanner` interface + `EventRecordsScanner` — ABI decode, `eth_getLogs` (from `core/scanner.go` + `scanner/scanner.go`)
- `StateStorage` interface + `SimpleStateStorage` — JSON file persistence (from `core/state.go` + `storage/state_storage.go`)
- `PostgresEventRecordWriter` — batch insert with `SaveAll` only (write half of `storage/event_records_storage.go`)
- `IndexerService` — WebSocket subscription + fan-out (from `service/indexer_service.go`)
- Deps: go-ethereum, pgx

### `services/api-server` — all query implementation
- `CacheStorage` interface + `RedisCacheStorage` — Redis get/set (from `core/cache.go` + `storage/cache_storage.go`)
- `PostgresEventRecordReader` — Squirrel query with `FindAll` only (read half of `storage/event_records_storage.go`)
- `SearchService` — cache-aside search (from `service/search_service.go`)
- HTTP handlers, server, schema (from `api/`)
- Deps: pgx, squirrel, go-redis, xxhash, msgpack

### `services/dashboard` — standalone
- No shared deps, no common module required

## Steps

### Step 1: Create `libs/common` module
- Create `libs/common/go.mod` with module path `eth-indexer/libs/common`, Go 1.24
- Create `libs/common/types.go`:
  - Move `EventRecord`, `EventRecordFilters`, `ComparisonFilter`, `ComparisonOp` from `core/event_record.go`
  - Define `EventRecordWriter` interface (`SaveAll`)
  - Define `EventRecordReader` interface (`FindAll`)
- No external dependencies — only stdlib (`context`, `time`)

### Step 2: Create `services/indexer` module
- Create `services/indexer/go.mod` requiring `eth-indexer/libs/common`
- `services/indexer/scanner.go` — merge `core/scanner.go` (interface) + `scanner/scanner.go` (impl) into one file
- `services/indexer/state.go` — merge `core/state.go` (interface) + `storage/state_storage.go` (impl)
- `services/indexer/state_test.go` — from `storage/state_storage_test.go`
- `services/indexer/worker.go` — from `core/worker.go`, depends on local `Scanner` + `common.EventRecordWriter`
- `services/indexer/storage.go` — `PostgresEventRecordWriter` with only `SaveAll` + batch insert logic
- `services/indexer/service.go` — from `service/indexer_service.go`, updated to use local types
- `services/indexer/config.go` — indexer-specific config (RPC URL, ABI, events, confirmedAfter, postgres)
- `services/indexer/main.go` — from `cmd/eth-indexer/main.go`, stripped of search/API concerns

### Step 3: Create `services/api-server` module
- Create `services/api-server/go.mod` requiring `eth-indexer/libs/common`
- `services/api-server/cache.go` — merge `core/cache.go` (interface) + `storage/cache_storage.go` (impl)
- `services/api-server/storage.go` — `PostgresEventRecordReader` with only `FindAll` + Squirrel query + `makePredicate` helpers
- `services/api-server/service.go` — from `service/search_service.go`, depends on local `CacheStorage` + `common.EventRecordReader`
- `services/api-server/handlers.go` — from `api/handlers.go`, remove `IndexerService` dep and `State` handler
- `services/api-server/server.go` — from `api/server.go`, remove `/status` route
- `services/api-server/schema.go` — from `api/schema.go`
- `services/api-server/config.go` — search-specific config (API port, TTL, postgres, redis, topics)
- `services/api-server/main.go` — only PG, Redis, SearchService, HTTP server

### Step 4: Create `services/dashboard` module
- Create `services/dashboard/go.mod` (standalone, no common dep)
- Move `cmd/dashboard/main.go` → `services/dashboard/main.go`

### Step 5: Create root `go.work`
```go
go 1.24.0

use (
    ./libs/common
    ./services/indexer
    ./services/api-server
    ./services/dashboard
)
```

### Step 6: Clean up root
- Remove old `go.mod`, `go.sum` from root
- Remove old `cmd/`, `api/`, `service/`, `core/`, `storage/`, `scanner/`, `config/` dirs
- Keep `migrations/`, `monitoring/`, `test/`, `docker-compose.yml`, `Makefile`

### Step 7: Update Dockerfiles
- Each service gets its own `Dockerfile` in `services/<name>/`
- Build context is root dir; copy `go.work` + `libs/` + target `services/<name>/`
- Multi-stage build: builder stage compiles, final stage copies binary

### Step 8: Update `docker-compose.yml`
- Add `api-server` service (depends on postgres, valkey)
- Update `indexer` service build context + dockerfile path
- Update `dashboard` service build context + dockerfile path
- Remove port mapping from `indexer` (headless)
- Expose port on `api-server` only

### Step 9: Update `Makefile`
- Per-service build targets: `build-indexer`, `build-api-server`, `build-dashboard`
- Per-service run targets: `run-indexer`, `run-api-server`
- `build-all` / `test-all` / `tidy-all` aggregate targets

## File Migration Map

| Current Location | New Location |
|---|---|
| `core/event_record.go` | `libs/common/types.go` (types + split interfaces) |
| `core/scanner.go` | `services/indexer/scanner.go` (merged with impl) |
| `core/cache.go` | `services/api-server/cache.go` (merged with impl) |
| `core/state.go` | `services/indexer/state.go` (merged with impl) |
| `core/worker.go` | `services/indexer/worker.go` |
| `scanner/scanner.go` | `services/indexer/scanner.go` (merged with interface) |
| `storage/event_records_storage.go` SaveAll part | `services/indexer/storage.go` |
| `storage/event_records_storage.go` FindAll part | `services/api-server/storage.go` |
| `storage/cache_storage.go` | `services/api-server/cache.go` (merged with interface) |
| `storage/state_storage.go` | `services/indexer/state.go` (merged with interface) |
| `storage/state_storage_test.go` | `services/indexer/state_test.go` |
| `service/indexer_service.go` | `services/indexer/service.go` |
| `service/search_service.go` | `services/api-server/service.go` |
| `api/handlers.go` | `services/api-server/handlers.go` |
| `api/server.go` | `services/api-server/server.go` |
| `api/schema.go` | `services/api-server/schema.go` |
| `cmd/eth-indexer/main.go` | `services/indexer/main.go` |
| `cmd/dashboard/main.go` | `services/dashboard/main.go` |
| `config/config.go` | split into `services/indexer/config.go` + `services/api-server/config.go` |
| `go.mod` | removed (replaced by per-module go.mod + go.work) |

## Dependency Graph

```
libs/common (zero external deps)
  ↑
  ├── services/indexer (go-ethereum, pgx)
  └── services/api-server (pgx, squirrel, go-redis, xxhash, msgpack)

services/dashboard (kafka-go) — standalone, no shared dep
```

## Key Decisions
- **Thin shared lib**: `libs/common` contains only types and interfaces — no implementations, no external deps
- **Interface segregation**: `EventRecordWriter` (indexer) / `EventRecordReader` (api-server) instead of one fat interface
- **Colocation**: each interface + implementation merged into one file per service (e.g., `Scanner` interface + `EventRecordsScanner` both in `services/indexer/scanner.go`)
- **Independent dependency trees**: indexer doesn't pull squirrel/redis; api-server doesn't pull go-ethereum
- **`go.work` for local dev** — CI/Docker builds use workspace mode (`GOWORK=on`)