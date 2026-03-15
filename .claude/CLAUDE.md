# eth-indexer

This service indexes specific Ethereum smart contract events and stores them in PostgreSQL for fast, structured querying.

## Skills
- Languages: Go
- Libraries: go-ethereum, pgx, squirrel, go-redis
- Storage: PostgreSQL, Redis/Valkey (cache)
- Deployment: Docker

## What It Does

- Connects to Ethereum via WebSocket RPC
- Subscribes to new block headers (`SubscribeNewHead`)
- Filters logs by contract address + event topic0
- Decodes ABI-encoded data (indexed topics + non-indexed data)
- Normalizes values for storage
- Bulk inserts records into PostgreSQL
- Exposes search API with Redis cache-aside

## Key Design Principles

- **Deterministic** — replaying blocks produces identical results
- **Idempotent** — primary key is `(tx_hash, log_index)`; duplicates are silently ignored
- **Reorg-safe** — only indexes blocks after `confirmedAfter` depth
- **Search-optimized** — data structured for efficient filtering and pagination

## Architecture

### Indexing Pipeline

```
Ethereum RPC (WebSocket)
→ IndexerService.SubscribeNewHead
→ indexAll() — fans out to all workers concurrently
→ Worker.IndexBlocks(blockNumber)
→ EventRecordsScanner.Scan (FilterLogs + ABI decode)
→ PostgreSQL bulk insert (ON CONFLICT DO NOTHING)
→ SimpleStateStorage (JSON file, last block per event)
```

### Query Pipeline

```
HTTP Client
→ GET /search/{topic}
→ SearchService (cache-aside)
  → Redis hit  → return cached result
  → Redis miss → PostgreSQL query → write cache
→ JSON response
```

## Key Components

- **IndexerService** (`service/indexer_service.go`): Manages WebSocket subscription; on each new block calls `IndexBlocks` on all workers concurrently via goroutines.
- **Worker** (`core/worker.go`): Per-event processor. Calculates confirmed block range (`lastBlock+1` to `blockNumber-confirmedAfter`) and delegates to Scanner.
- **EventRecordsScanner** (`scanner/scanner.go`): Calls `eth_getLogs`, validates topic0, ABI-decodes indexed (topics[1:]) and non-indexed (log.Data) fields.
- **PostgresEventRecordsStorage** (`storage/event_records_storage.go`): Bulk inserts via pgx batch; queries via Squirrel with JSONB containment support.
- **SearchService** (`service/search_service.go`): Cache-aside with deterministic key (`xxhash64(msgpack(normalizedFilters))`).
- **SimpleStateStorage** (`storage/state_storage.go`): Persists `event_name → last_block_number` as a JSON file for resume-safe restarts.

## Storage Strategy

- Primary key: `(tx_hash, log_index)` — uniquely identifies each event log
- Confirmed-only indexing: `safeBlock = latestBlock - confirmedAfter`
- Immutable documents — no rollback required
- JSONB `data` column stores all decoded event parameters

## Query Layer

- Accepts filters: `contract_address`, `tx_hash`, `block_hash`, `block_number`, `log_index`, `timestamp`, `data`
- Comparison filters (`gte`, `lte`, `gt`, `lt`, `eq`) on `block_number` and `timestamp`
- JSONB containment (`@>`) for `data` field queries
- Results cached in Redis with configurable TTL

## Operational Characteristics

- Resume-safe via persisted block state (JSON file)
- Bulk ingestion for high throughput
- Per-event worker goroutines run concurrently per block
- Horizontally scalable
- Suitable for high-volume EVM chains

---

This system provides a reliable, production-grade pipeline for indexing and querying Ethereum event data at scale.
