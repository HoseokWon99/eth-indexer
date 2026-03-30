# eth-indexer

This system indexes specific Ethereum smart contract events and stores them in MongoDB for fast, structured querying. It is structured as a **monorepo** with three independent services and two shared libraries.

## Skills
- Languages: Go
- Libraries: go-ethereum, pgx (legacy Postgres impl), mongo-driver/v2, squirrel, go-redis, kafka-go
- Storage: MongoDB (primary), Redis/Valkey (cache), Kafka
- Deployment: Docker Compose (local dev), Kubernetes / minikube (production)

## Repository Layout

```
libs/
  common/       — shared types: EventRecord, ComparisonFilter[T], PagingOptions[CursorT]
  config/       — shared Postgres helpers: PostgresOptions, LoadPostgresFromEnv, CreatePgConnPool
services/
  indexer/      — standalone indexer service
  api-server/   — standalone HTTP query service
  dashboard/    — Kafka CDC event router (routes Debezium CDC messages to per-event topics)
monitoring/
  prometheus/   — prometheus.yml (scrape config; used by Docker Compose volume mount)
  grafana/      — provisioning: datasources, dashboard provider, eth-indexer.json dashboard
  debezium/     — register-connector.sh (used by Docker Compose volume mount)
k8s/
  namespace.yaml, secrets.yaml, gateway.yaml, external-services.yaml
  kafka-connect/ — Deployment + Service + debezium-configmap.yaml + debezium-init-job.yaml
  dashboard/    — Deployment
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
- Bulk upserts records into MongoDB (idempotent via `$setOnInsert`)
- Exposes search API with Redis cache-aside

## Key Design Principles

- **Deterministic** — replaying blocks produces identical results
- **Idempotent** — primary key is `(tx_hash, log_index)`; duplicates are silently ignored
- **Reorg-safe** — only indexes blocks after `confirmedAfter` depth
- **Search-optimized** — data structured for efficient filtering and pagination

## Storage Strategy

- Document `_id`: `"{tx_hash}:{log_index}"` — uniquely identifies each event log
- Confirmed-only indexing: `safeBlock = latestBlock - confirmedAfter`
- Immutable documents — no rollback required; upsert uses `$setOnInsert` (idempotent)
- `data` field stores all decoded event parameters
- `topic` field is sourced from `record.Topic` (not passed as a separate argument)
- Results cached in Redis with configurable TTL

## Operational Characteristics

- Resume-safe via persisted block state (JSON file, flushed on shutdown)
- Bulk ingestion for high throughput
- Per-scanner goroutines run concurrently per block (one goroutine per scanner in `indexAll`)
- Services are independently deployable
- Suitable for high-volume EVM chains

## Detailed Docs

- @.claude/architecture.md — Indexing, Query, and CDC/Monitoring pipelines
- @.claude/services.md — Shared libs, Indexer, API Server, Dashboard internals
- @.claude/kubernetes.md — Secrets, cluster scripts, apply order, port-forwards