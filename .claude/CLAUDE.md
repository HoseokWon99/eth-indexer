# eth-indexer

This system indexes specific Ethereum smart contract events and stores them in PostgreSQL for fast, structured querying. It is structured as a **monorepo** with three independent services and two shared libraries.

## Skills
- Languages: Go
- Libraries: go-ethereum, pgx, squirrel, go-redis, kafka-go
- Storage: PostgreSQL, Redis/Valkey (cache), Kafka
- Deployment: Docker Compose (local dev), Kubernetes / minikube (production)

## Repository Layout

```
libs/
  common/       — shared types: EventRecord, ComparisonFilter[T], PagingOptions[CursorT]
  config/       — shared Postgres helpers: PostgresOptions, LoadPostgresFromEnv, CreatePgConnPool
services/
  indexer/      — standalone indexer service
  api-server/   — standalone HTTP query service
  kafka-router/ — Kafka CDC event router (routes Debezium CDC messages to per-event topics)
monitoring/
  prometheus/   — prometheus.yml (scrape config; used by Docker Compose volume mount)
  grafana/      — provisioning: datasources, dashboard provider, eth-indexer.json dashboard
  debezium/     — register-connector.sh (used by Docker Compose volume mount)
k8s/
  namespace.yaml, secrets.yaml, gateway.yaml, external-services.yaml
  kafka-connect/ — Deployment + Service + debezium-configmap.yaml + debezium-init-job.yaml
  kafka-router/ — Deployment
  indexer/      — Deployment + ConfigMap
  api-server/   — Deployment + Service
  monitoring/
    kafka-exporter/ — Deployment + Service
    prometheus/     — ConfigMap + Deployment + Service
    grafana/        — ConfigMaps (datasources, dashboard provider, dashboard JSON) + Deployment + Service
scripts/
  k8s/
    cluster-up.sh   — start minikube, build images, apply all manifests
    cluster-down.sh — delete minikube cluster
  anvil/        — deploy-contracts.sh, wait-for-rpc.sh
  test/         — setup-test-env.sh, teardown-test-env.sh
  monitor.sh, psql.sh
```

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
→ Indexer.Run (SubscribeNewHead)
→ indexAll() — fans out to all scanners concurrently (one goroutine per scanner)
→ EventRecordsScanner.Scan (FilterLogs + ABI decode)
→ PostgresEventRecordsStorage.SaveAll (bulk insert, ON CONFLICT DO NOTHING)
→ SimpleStateStorage.SetLastBlockNumber (in-memory; flushed to JSON file on close)
```

### Query Pipeline

```
HTTP Client
→ GET /search/{topic}
→ Handler.Search (cache-aside)
  → Redis hit  → return cached result
  → Redis miss → PostgreSQL query → write cache
→ JSON response
```

### CDC / Monitoring Pipeline

```
PostgreSQL (WAL)
→ Debezium (Kafka Connect) — CDC via pgoutput plugin
→ Kafka topic: eth-indexer.public.event_records
→ Kafka Router — routes to eth-indexer.events.{eventType}
→ kafka-exporter — exposes Kafka metrics to Prometheus
→ Prometheus — scrapes kafka-exporter:9308
→ Grafana — visualizes event ingestion rate, consumer lag, totals
```

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

## Kafka Router Service (`services/kafka-router/`)

- **`main.go`**: Reads from a Debezium CDC Kafka topic (`SOURCE_TOPIC`, default: `eth-indexer.public.event_records`), extracts the `topic` field from each row, and routes messages to `{DEST_TOPIC_PREFIX}.{eventType}` (default prefix: `eth-indexer.events`).
- Env vars: `KAFKA_BOOTSTRAP_SERVERS`, `SOURCE_TOPIC`, `DEST_TOPIC_PREFIX`.
- Uses `segmentio/kafka-go` for consumer/producer. Commits offsets only after successful write. Graceful shutdown on SIGTERM/SIGINT.

## Monitoring Stack

All monitoring components run in the `eth-indexer` namespace alongside application services.

- **kafka-exporter** (`danielqsj/kafka-exporter`) — scrapes Kafka broker at `kafka:9092`, exposes metrics on `:9308`
- **Prometheus** (`prom/prometheus`) — scrapes `kafka-exporter:9308` every 15s; 7-day retention
- **Grafana** (`grafana/grafana`) — pre-provisioned with Prometheus datasource and the ETH Indexer dashboard
  - Dashboard panels: event ingestion rate, total records by event type, events in last 5 min, consumer lag, broker count, total CDC events captured
  - Access: `http://localhost:3000` via port-forward; credentials from `grafana-credentials` Secret

Source configs in `monitoring/` are used by Docker Compose. The k8s equivalents live in `k8s/monitoring/` as ConfigMaps.

## Kubernetes Deployment

### Secrets (`k8s/secrets.yaml`)

| Secret | Keys |
|---|---|
| `postgres-credentials` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` |
| `valkey-credentials` | `REDIS_PASSWORD` |
| `rpc-credentials` | `RPC_URL` |
| `grafana-credentials` | `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD` |

### Cluster Scripts

```bash
# Start minikube cluster, build images, apply all manifests
scripts/k8s/cluster-up.sh

# Tear down cluster
scripts/k8s/cluster-down.sh
```

`cluster-up.sh` requires these env vars (or a `.env` file):
`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `REDIS_PASSWORD`, `RPC_URL`, `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD`, `GATEWAY_HOST`, `POSTGRES_HOST`, `REDIS_HOST`, `KAFKA_HOST`

### Apply Order (manual)

```bash
kubectl apply -f k8s/namespace.yaml
envsubst < k8s/secrets.yaml | kubectl apply -f -
envsubst < k8s/external-services.yaml | kubectl apply -f -
kubectl apply -f k8s/kafka-connect/
kubectl apply -f k8s/indexer/ && kubectl apply -f k8s/api-server/ && kubectl apply -f k8s/kafka-router/
envsubst < k8s/gateway.yaml | kubectl apply -f -
kubectl apply -f k8s/monitoring/
```

### Port-forwards

```bash
kubectl port-forward -n eth-indexer svc/api-server 8080:80
kubectl port-forward -n eth-indexer svc/grafana 3000:3000
kubectl port-forward -n eth-indexer svc/prometheus 9090:9090
```

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

- Resume-safe via persisted block state (JSON file, flushed on shutdown)
- Bulk ingestion for high throughput
- Per-scanner goroutines run concurrently per block (one goroutine per scanner in `indexAll`)
- Services are independently deployable
- Suitable for high-volume EVM chains

---

This system provides a reliable, production-grade pipeline for indexing and querying Ethereum event data at scale.
