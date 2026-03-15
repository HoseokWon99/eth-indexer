# Plan: Separate Search API from Indexer

## Goal
Split the monolithic `eth-indexer` binary into two independent services:
- **eth-indexer**: headless indexer (Ethereum RPC → PostgreSQL)
- **search-api**: stateless HTTP search API (PostgreSQL + Redis → HTTP clients)

The search API can be horizontally scaled independently.

```
Client <-> search-api (N instances) <-> PostgreSQL/Redis <-> eth-indexer
```

## Steps

### Step 1: Decouple `api/handlers.go` from IndexerService
- Remove `IndexerService` dependency from `Handler` struct
- Remove `State` handler (stays on indexer side)
- `Handler` only needs `SearchService` + `topics`
- Remove unused imports (`service.IndexerService`)

### Step 2: Update `api/server.go` routes
- Remove `/status` route (indexer-only)
- Keep `/health` and `/search/{topic}`

### Step 3: Split config
- Create `config/search_config.go` with `SearchConfig` struct containing only: `API`, `Postgres`, `Redis`, and a `Topics []string` field
- Keep existing `Config` for the indexer binary

### Step 4: Create `cmd/search-api/main.go`
New entrypoint that initializes only:
- PostgreSQL connection (read queries)
- Redis connection (cache)
- `SearchService` + `Handler` + `Server`
- Loads `SearchConfig`

No Ethereum client, no scanners, no workers, no state file.

### Step 5: Trim `cmd/eth-indexer/main.go`
- Remove Redis client, `SearchService`, search `Handler` setup
- Remove `api.Server` — indexer becomes headless (or keeps a minimal `/health` + `/status` HTTP server directly)
- Remove `api` package import

### Step 6: Update `Dockerfile`
- Add multi-target build: build both `eth-indexer` and `search-api` binaries
- Or create a separate `Dockerfile.search-api`

### Step 7: Update `docker-compose.yml`
- Add `search-api` service with its own config
- Remove port mapping from `indexer` (no longer serves client traffic)
- `search-api` depends on `postgres` and `valkey`

### Step 8: Update `Makefile`
- Add `build-search-api` target
- Update `build` to build both binaries
- Add `run-search-api` target

## Files Changed
- `api/handlers.go` — remove IndexerService dependency, remove State handler
- `api/server.go` — remove /status route
- `config/config.go` — (optional) add SearchConfig or keep as-is with optional fields
- `cmd/search-api/main.go` — **new file**
- `cmd/eth-indexer/main.go` — strip search/API concerns
- `Dockerfile` — add search-api build target
- `docker-compose.yml` — add search-api service
- `Makefile` — add search-api targets

## What stays unchanged
- `core/` — all types and interfaces
- `storage/` — PostgresEventRecordsStorage, RedisCacheStorage
- `service/search_service.go` — used by search-api
- `service/indexer_service.go` — used by eth-indexer
- `scanner/` — used by eth-indexer only