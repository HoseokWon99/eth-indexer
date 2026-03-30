# Services

## Shared Libraries

### `libs/common`
- `EventRecord` — the canonical event document stored in MongoDB. `Topic` field is set by the scanner and persisted directly (not passed as a separate `SaveAll` argument).
- `ComparisonFilter[T]` — typed map of `lt/lte/gt/gte/eq` operators
- `PagingOptions[CursorT]` — generic pagination struct with cursor and limit

### `libs/config`
- `PostgresOptions` / `LoadPostgresFromEnv()` — loads Postgres config from env vars (legacy; still used by `PostgresEventRecordsStorage`)
- `CreatePgConnPool()` — creates a `pgx.ConnPool` with optional TLS (legacy)

## Indexer Service (`services/indexer/`)

- **`main.go`**: Wires up config, MongoDB/Postgres storage, state storage, scanners, and `Indexer`; calls `indexer.Run(ctx)`.
- **`config/config.go`**: Loads indexer options from env vars (`INDEXER_*`, `MONGODB_*`). Config fields: `rpc_url`, `contract_addresses`, `abi`, `event_names`, `confirmed_after`, `offset_block_number`, `status_file_path`.
- **`core/indexer.go`** (`Indexer`): Manages WebSocket subscription. On each new head, `indexAll()` fans out to all scanners concurrently. Reads/writes state via `StateStorage`; saves state on `Close()`.
- **`core/scanner.go`** (`Scanner` interface): `Topic0()`, `EventName()`, `Scan(ctx, from, to)`.
- **`core/storage.go`**: `StateStorage` and `EventRecordsStorage` interfaces. `SaveAll(ctx, records)` — no `topic` argument; `record.Topic` carries the value.
- **`scanner/scanner.go`** (`EventRecordsScanner`): Calls `eth_getLogs`, validates topic0, ABI-decodes indexed (topics[1:]) and non-indexed (log.Data) fields. Returns records sorted by block number.
- **`storage/mongo_event_records_storage.go`** (`MongoEventRecordsStorage`): Bulk upserts via `BulkWrite` with `$setOnInsert` + `upsert:true`. `_id` is `"{tx_hash}:{log_index}"`.
- **`storage/event_records_storage.go`** (`PostgresEventRecordsStorage`): Legacy Postgres bulk insert via pgx batch. `topic` is now read from `record.Topic` per-record.
- **`storage/state_storage.go`** (`SimpleStateStorage`): In-memory map of `event_name → last_block_number`, persisted as a JSON file. Initializes unknown events to `offset_block_number`.

## API Server Service (`services/api-server/`)

- **`main.go`**: Wires up MongoDB reader, Redis cache, `Handler`, and `Server`.
- **`config/config.go`**: Loads all config from env vars (`API_PORT`, `API_TTL`, `REDIS_*`, `MONGODB_*`, `TOPICS`). Creates the Redis client with optional TLS.
- **`core/storage.go`**: `EventRecordsStorage` (`FindAll`) and `CacheStorage` (`Get`/`Set`) interfaces.
- **`types/types.go`**: `EventRecordFilters`, `EventRecordCursor`, `SearchResponse` — service-local types.
- **`storage/event_records_storage.go`**: Queries `event_records` collection. Supports `=`, `IN`, comparison ops (`lt/lte/gt/gte/eq`) on `block_number`/`timestamp`, and sub-document matching on `data`. Cursor-based pagination on `(block_number, log_index)`.
- **`storage/cache_storage.go`** (`RedisCacheStorage`): Wraps go-redis for get/set with TTL. Key prefix: `eth-indexer:cache:`.
- **`api/handlers.go`** (`Handler`): Cache-aside pattern inline — tries cache by topic+query-string key, on miss queries DB and writes cache back. Validates topic against allowlist.
- **`api/server.go`** (`Server`): HTTP server with graceful shutdown. Routes: `GET /health`, `GET /search/{topic}`.

## Dashboard Service (`services/dashboard/`)

- **`main.go`**: Reads from a Debezium CDC Kafka topic (`SOURCE_TOPIC`, default: `eth-indexer.eth_indexer.event_records`), extracts the `topic` field from each document, and routes messages to `{DEST_TOPIC_PREFIX}.{eventType}` (default prefix: `eth-indexer.events`).
- Env vars: `KAFKA_BOOTSTRAP_SERVERS`, `SOURCE_TOPIC`, `DEST_TOPIC_PREFIX`.
- Uses `segmentio/kafka-go` for consumer/producer. Commits offsets only after successful write. Graceful shutdown on SIGTERM/SIGINT.
