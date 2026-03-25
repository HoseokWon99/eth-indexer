# Services

## Shared Libraries

### `libs/common`
- `EventRecord` — the canonical event document stored in Postgres
- `ComparisonFilter[T]` — typed map of `lt/lte/gt/gte/eq` operators
- `PagingOptions[CursorT]` — generic pagination struct with cursor and limit

### `libs/config`
- `PostgresOptions` / `LoadPostgresFromEnv()` — loads Postgres config from env vars
- `CreatePgConnPool()` — creates a `pgx.ConnPool` with optional TLS

## Indexer Service (`services/indexer/`)

- **`main.go`**: Wires up config, Postgres pool, state storage, scanners, and `Indexer`; calls `indexer.Run(ctx)`.
- **`config/config.go`**: Loads indexer options from a JSON file (`INDEXER_CONFIG_PATH`, default `/etc/eth-indexer/indexer-config.json`) and Postgres options from env vars. Config fields: `rpc_url`, `contract_addresses`, `abi`, `event_names`, `confirmed_after`, `offset_block_number`, `status_file_path`.
- **`core/indexer.go`** (`Indexer`): Manages WebSocket subscription. On each new head, `indexAll()` fans out to all scanners concurrently. Reads/writes state via `StateStorage`; saves state on `Close()`.
- **`core/scanner.go`** (`Scanner` interface): `Topic0()`, `EventName()`, `Scan(ctx, from, to)`.
- **`core/storage.go`**: `StateStorage` and `EventRecordsStorage` interfaces.
- **`scanner/scanner.go`** (`EventRecordsScanner`): Calls `eth_getLogs`, validates topic0, ABI-decodes indexed (topics[1:]) and non-indexed (log.Data) fields. Returns records sorted by block number.
- **`storage/event_records_storage.go`** (`PostgresEventRecordsStorage`): Bulk inserts via pgx batch.
- **`storage/state_storage.go`** (`SimpleStateStorage`): In-memory map of `event_name → last_block_number`, persisted as a JSON file. Initializes unknown events to `offset_block_number`.

## API Server Service (`services/api-server/`)

- **`main.go`**: Wires up Postgres reader, Redis cache, `Handler`, and `Server`.
- **`config/config.go`**: Loads all config from env vars (`API_PORT`, `API_TTL`, `REDIS_*`, `TOPICS`). Creates the Redis client with optional TLS.
- **`core/storage.go`**: `EventRecordsStorage` (`FindAll`) and `CacheStorage` (`Get`/`Set`) interfaces.
- **`types/types.go`**: `EventRecordFilters`, `EventRecordCursor`, `SearchResponse` — service-local types.
- **`storage/event_records_storage.go`** (`PostgresEventRecordsStorage`): Queries `event_records` via Squirrel. Supports `=`, `IN`, comparison ops (`lt/lte/gt/gte/eq`), and JSONB containment (`@>`) on the `data` column. Cursor-based pagination on `(block_number, log_index)`.
- **`storage/cache_storage.go`** (`RedisCacheStorage`): Wraps go-redis for get/set with TTL. Key prefix: `eth-indexer:cache:`.
- **`api/handlers.go`** (`Handler`): Cache-aside pattern inline — tries cache by topic+query-string key, on miss queries DB and writes cache back. Validates topic against allowlist.
- **`api/server.go`** (`Server`): HTTP server with graceful shutdown. Routes: `GET /health`, `GET /search/{topic}`.

## Dashboard Service (`services/dashboard/`)

- **`main.go`**: Reads from a Debezium CDC Kafka topic (`SOURCE_TOPIC`, default: `eth-indexer.public.event_records`), extracts the `topic` field from each row, and routes messages to `{DEST_TOPIC_PREFIX}.{eventType}` (default prefix: `eth-indexer.events`).
- Env vars: `KAFKA_BOOTSTRAP_SERVERS`, `SOURCE_TOPIC`, `DEST_TOPIC_PREFIX`.
- Uses `segmentio/kafka-go` for consumer/producer. Commits offsets only after successful write. Graceful shutdown on SIGTERM/SIGINT.
