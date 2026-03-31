# eth-indexer

A production-grade Ethereum event indexer that captures smart contract events and stores them for fast, structured querying. Structured as a Go monorepo with three independent services and two shared libraries.

## Features

- **Deterministic indexing** - Replaying blocks produces identical results
- **Idempotent operations** - Primary key is `(tx_hash, log_index)`; duplicates are silently ignored
- **Reorg-safe** - Only indexes confirmed blocks (configurable depth)
- **High throughput** - Bulk insertion with automatic block range chunking
- **MongoDB storage** - Document-based event storage with idempotent upserts
- **Search API** - RESTful API with flexible filtering and cursor-based pagination
- **Resumable** - Persists indexer state per event, safe to restart
- **Real-time** - WebSocket-based block monitoring
- **Redis caching** - Query result caching with configurable TTL
- **Real-time dashboard** - Kafka CDC + Server-Sent Events UI
- **Docker-ready** - Complete containerization with Docker Compose
- **Kubernetes-ready** - Full manifests for minikube/production deployment
- **Monitoring** - Prometheus + Grafana + Kafka exporter

## Repository Layout

```
libs/
  common/       — shared types: EventRecord, ComparisonFilter[T], PagingOptions[CursorT]
  config/       — shared helpers: PostgresOptions, MongoOptions, LoadFromEnv, CreateConnPool
services/
  indexer/      — standalone Ethereum event indexer (multi-worker)
  api-server/   — standalone HTTP query service
  dashboard/    — real-time UI with Kafka CDC and SSE
monitoring/
  prometheus/   — prometheus.yml scrape config
  grafana/      — datasources, dashboard provider, dashboard JSON
  debezium/     — register-connector.sh
k8s/
  namespace.yaml, secrets.yaml, gateway.yaml, external-services.yaml
  kafka-connect/, dashboard/, indexer/, api-server/, monitoring/
scripts/
  k8s/          — cluster-up.sh, cluster-down.sh, test-cluster.sh
  anvil/        — deploy-contracts.sh, wait-for-rpc.sh
  test/         — setup-test-env.sh, teardown-test-env.sh
  monitor.sh, psql.sh
```

## Quick Start

### Local Development with Docker Compose

```bash
git clone <repository>
cd eth-indexer
cp .env.example .env
# Edit .env with your Ethereum RPC URL and contract config
```

Start all services:
```bash
make local-up
# or
docker compose -f docker-compose.local.yml up -d
```

Services started:
- **Anvil** - Local Ethereum node (port 8545)
- **MongoDB** - Primary event storage (port 27017)
- **Valkey (Redis)** - Query cache (port 6380)
- **Kafka + Zookeeper** - Event streaming (port 9092)
- **Kafka Connect + Debezium** - CDC connector (port 8083)
- **indexer** - ERC20 event indexer (health: port 8081)
- **indexer-staking** - StakingPool event indexer (health: port 8084)
- **indexer-uniswap** - UniswapPool event indexer (health: port 8085)
- **api-server** - HTTP query API (port 8082)
- **dashboard** - Real-time event UI (port 8090)
- **gateway** - Nginx reverse proxy (port 3003)

Monitor indexing:
```bash
./scripts/monitor.sh
```

Query events:
```bash
curl http://localhost:8082/search/Transfer | jq
```

### Running Services Directly (Go)

```bash
go mod download
make build-all
```

Each service is configured via environment variables. See the Configuration section below.

## Configuration

All services are configured via **environment variables**.

### MongoDB Options

| Variable | Default | Description |
|----------|---------|-------------|
| `MONGO_URI` | `mongodb://localhost:27017` | MongoDB connection URI |
| `MONGO_DB` | `eth_indexer` | Database name |
| `MONGO_USER` | - | Username (optional if in URI) |
| `MONGO_PASSWORD` | - | Password (optional if in URI) |

### Indexer Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ETHEREUM_RPC_URL` | Yes | - | WebSocket RPC endpoint (`wss://` or `ws://`) |
| `INDEXER_CONFIRMED_AFTER` | No | `12` | Blocks to wait before indexing (reorg protection) |
| `INDEXER_OFFSET_BLOCK_NUMBER` | No | `0` | Starting block number |
| `INDEXER_STATUS_FILE_PATH` | No | `/var/lib/indexer/state.json` | Path to persist indexer state |
| `API_PORT` | No | `8080` | Health check endpoint port |

The indexer supports multiple workers. Each worker is configured with `INDEXER_WORKER_N_*` variables (N = 0, 1, 2, ...):

| Variable | Required | Description |
|----------|----------|-------------|
| `INDEXER_WORKER_N_ABI_PATH` | Yes | Path to contract ABI JSON file |
| `INDEXER_WORKER_N_CONTRACT_ADDRESSES` | Yes | Comma-separated contract addresses |
| `INDEXER_WORKER_N_EVENT_NAMES` | Yes | Comma-separated event names to index |
| `INDEXER_WORKER_N_NAME` | No | Worker name for logging (default: `worker-N`) |

### API Server Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `API_PORT` | No | `8080` | HTTP server port |
| `API_TTL` | No | `60` | Redis cache TTL in seconds |
| `TOPICS` | No | - | Comma-separated allowed event topics |
| `REDIS_HOST` | No | - | Valkey/Redis host |
| `REDIS_PORT` | No | `6379` | Valkey/Redis port |
| `REDIS_PASSWORD` | No | - | Valkey/Redis password |
| `REDIS_DB` | No | `0` | Redis database index |
| `REDIS_CA_CERT_PATH` | No | - | TLS CA certificate path |

### Dashboard Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KAFKA_BOOTSTRAP_SERVERS` | `kafka:9092` | Kafka broker address |
| `SOURCE_TOPIC` | `eth-indexer.eth_indexer.event_records` | Debezium CDC topic |
| `TOPICS` | `Transfer,Approval` | Event names to display |
| `UI_PORT` | `8090` | Dashboard HTTP port |
| `API_SERVER_URL` | `http://api-server` | API server base URL |

## API Endpoints

Full API documentation: [API.md](API.md)

### Health Check
```
GET /health  →  200 OK
```

### Search Events
```
GET /search/{topic}?[filters]
```

**Response:**
```json
{
  "count": 150,
  "result": [
    {
      "topic": "Transfer",
      "contract_address": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      "tx_hash": "0x023814...",
      "block_hash": "0xf4c508...",
      "block_number": 24633117,
      "log_index": 0,
      "data": {
        "from": "0x9250e9...",
        "to": "0xf8e16e...",
        "value": "500"
      },
      "timestamp": "2026-03-11T08:47:18.630617Z"
    }
  ],
  "next_cursor": "..."
}
```

### Filter Parameters

| Parameter | Format | Example |
|-----------|--------|---------|
| `contract_address` | Comma-separated addresses | `?contract_address=0xA0b8...` |
| `tx_hash` | Exact match | `?tx_hash=0x0238...` |
| `block_hash` | Exact match | `?block_hash=0xf4c5...` |
| `log_index` | Comma-separated integers | `?log_index=0,1,2` |
| `block_number` | JSON comparison object | `?block_number={"gte":100,"lte":200}` |
| `timestamp` | JSON comparison object | `?timestamp={"gte":"2026-01-01T00:00:00Z"}` |
| `data` | JSON containment | `?data={"from":"0x..."}` |

Comparison operators: `gte`, `lte`, `gt`, `lt`, `eq`

**Examples:**
```bash
# Block range
curl --get http://localhost:8082/search/Transfer \
  --data-urlencode 'block_number={"gte":24633120,"lte":24633130}'

# Contract + block range + log index
curl --get http://localhost:8082/search/Transfer \
  --data-urlencode 'contract_address=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48' \
  --data-urlencode 'block_number={"gte":24633120}' \
  --data-urlencode 'log_index=0'

# JSONB / document field filter
curl --get http://localhost:8082/search/Transfer \
  --data-urlencode 'data={"from":"0x9250e9ab0ffe3590629746843bb39425c4b2e3da"}'
```

## Architecture

### Indexing Pipeline

```mermaid
flowchart LR
    ETH(["Ethereum Node\nWebSocket RPC"])

    subgraph Indexer["Indexer Service"]
        IS["IndexerService\nSubscribeNewHead"]
        W["Worker N\nper event type"]
        SC["Scanner\nFilterLogs + ABI Decode"]
        ST["State File\nlast block per worker"]
    end

    DB[("MongoDB")]

    ETH -- "block headers" --> IS
    IS -- "confirmed block range" --> W
    W -- "scan range" --> SC
    SC -- "eth_getLogs" --> ETH
    SC -- "decoded records" --> W
    W -- "bulk upsert" --> DB
    IS -- "save / load" --> ST
```

### Query Pipeline

```mermaid
flowchart LR
    CLIENT(["HTTP Client"])

    subgraph API["API Layer"]
        SRV["HTTP Server"]
        SS["SearchService\ncache-aside"]
    end

    RD[("Redis / Valkey\nQuery Cache")]
    DB[("MongoDB")]

    CLIENT -- "GET /search/{topic}" --> SRV
    SRV -- "filters" --> SS
    SS -- "cache hit" --> RD
    RD -- "cached result" --> SS
    SS -- "cache miss" --> DB
    DB -- "records" --> SS
    SS -- "write cache" --> RD
    SS -- "response" --> SRV
    SRV -- "JSON" --> CLIENT
```

### CDC / Dashboard Pipeline

```mermaid
flowchart LR
    DB[("MongoDB")]
    DZ["Debezium\nKafka Connect"]
    KF[("Kafka\nCDC topic")]
    DS["Dashboard Service\nKafka consumer"]
    SSE["SSE Hub\n/events endpoint"]
    UI(["Browser\nReal-time UI"])

    DB -- "change stream" --> DZ
    DZ -- "CDC messages" --> KF
    KF -- "consume" --> DS
    DS -- "broadcast" --> SSE
    SSE -- "Server-Sent Events" --> UI
```

### Key Components

- **Indexer Service**: Subscribes to Ethereum block headers via WebSocket, fans out to per-event worker goroutines, bulk-upserts decoded records into MongoDB
- **Scanner**: Calls `eth_getLogs` RPC, validates topic0, ABI-decodes indexed topics and non-indexed data fields
- **API Server**: RESTful API with cache-aside pattern; queries MongoDB with flexible filter support
- **Dashboard**: Consumes Debezium CDC messages from Kafka and streams to browser clients via SSE
- **Storage**: MongoDB upserts via `$setOnInsert` keyed on `{tx_hash}:{log_index}`; records grouped by topic with nested children array
- **Cache**: Redis/Valkey with deterministic key from query parameters, configurable TTL
- **State**: JSON file tracking last indexed block per worker; enables safe resumption after restarts

## Cache Structure

The API server uses a **cache-aside** pattern backed by Redis/Valkey.

### Key Format

```
eth-indexer:cache:{topic}?{raw_query_string}
```

Example:
```
eth-indexer:cache:Transfer?contract_address=0xA0b8...&block_number={"gte":100}
```

### Value Structure

The full `SearchResponse` is cached as a JSON string:

```json
{
  "count": 42,
  "result": [ { ...EventRecord }, { ...EventRecord } ],
  "next_cursor": "..."
}
```

### Redis Storage Structure

```mermaid
graph TD
    REDIS[("Redis / Valkey\nDB 0")]

    NS["prefix: eth-indexer:cache:"]

    subgraph KEY_FORMAT["key = prefix + topic + '?' + raw_query_string"]
        K1["eth-indexer:cache:Transfer?contract_address=0xA0b8..."]
        K2["eth-indexer:cache:Transfer?block_number=gte:100,lte:200"]
        K3["eth-indexer:cache:Transfer?contract_address=0xA0b8...&log_index=0"]
        KN["eth-indexer:cache:Approval?..."]
    end

    V1["STRING  TTL: 60s\n{count:N, result:[...], next_cursor:'...'}"]
    V2["STRING  TTL: 60s\n{count:N, result:[...], next_cursor:'...'}"]
    V3["STRING  TTL: 60s\n{count:N, result:[...], next_cursor:'...'}"]
    VN["STRING  TTL: 60s\n{count:N, result:[...], next_cursor:'...'}"]

    REDIS --> NS --> KEY_FORMAT
    K1 --> V1
    K2 --> V2
    K3 --> V3
    KN --> VN
```

### Cache Key Properties

- **Scope**: per topic + per exact query string combination
- **Serialization**: JSON
- **TTL**: configurable via `API_TTL` env var (default: 60s)
- **On Redis failure (GET)**: request fails with 500
- **On Redis failure (SET)**: warning logged, fresh response still returned

## Database Schema

Records are grouped by event topic in MongoDB. Each document holds all records for one event type:

```json
{
  "_id": "Transfer",
  "topic": "Transfer",
  "children": [
    {
      "contract_address": "0x...",
      "tx_hash": "0x...",
      "block_hash": "0x...",
      "block_number": 24633117,
      "log_index": 0,
      "data": { "from": "0x...", "to": "0x...", "value": "500" },
      "timestamp": "2026-03-11T08:47:18Z"
    }
  ]
}
```

Idempotency is enforced via `$setOnInsert` upserts keyed on `{tx_hash}:{log_index}`.

```mermaid
graph TD
    COL[("event_records\ncollection")]

    DOC1["_id: Transfer\ntopic: Transfer"]
    DOC2["_id: Approval\ntopic: Approval"]

    C1["children[0]\ncontract_address\ntx_hash · log_index\nblock_number · block_hash\ndata · timestamp"]
    C2["children[1]\ncontract_address\ntx_hash · log_index\nblock_number · block_hash\ndata · timestamp"]
    C3["children[N]\n..."]

    C4["children[0]\ncontract_address\ntx_hash · log_index\nblock_number · block_hash\ndata · timestamp"]
    C5["children[N]\n..."]

    COL --> DOC1
    COL --> DOC2
    DOC1 --> C1
    DOC1 --> C2
    DOC1 --> C3
    DOC2 --> C4
    DOC2 --> C5
```

## Utility Scripts

```bash
# Monitor indexing progress
./scripts/monitor.sh
```

## Kubernetes Deployment

Full guide: [k8s/README.md](k8s/README.md)

```bash
# Start minikube, build images, and apply all manifests
make cluster-up
# or
./scripts/k8s/cluster-up.sh

# Tear down
make cluster-down
```

Apply order:
1. `namespace.yaml`
2. `secrets.yaml`
3. `external-services.yaml`
4. `kafka-connect/`
5. `indexer/`
6. `api-server/`
7. `dashboard/`
8. `monitoring/`
9. `gateway.yaml`

## Build & Test

```bash
# Build all services
make build-all

# Run Go unit tests
make test-unit

# Run end-to-end tests (requires local Docker Compose)
make test-e2e

# Build Solidity contracts (Forge)
make contracts-build

# Setup / teardown test environment
./scripts/test/setup-test-env.sh
./scripts/test/teardown-test-env.sh

# Lint
make lint

# Tidy all Go modules
make tidy-all
```

## Production Considerations

### Confirmation Depth
Set `INDEXER_CONFIRMED_AFTER` based on chain finality:
- **Ethereum mainnet**: 12+ blocks
- **L2s (Optimism, Arbitrum)**: 1–5 blocks
- **Sidechains**: Varies

### Starting Block
- Set `INDEXER_OFFSET_BLOCK_NUMBER` to a recent block for initial testing
- Start from block 0 only if complete history is needed
- Consider backfilling separately for large ranges

### High-Volume Contracts
The indexer automatically handles high event rates:
- Starts with 50-block chunks
- Reduces chunk size when hitting RPC limits
- Works with any RPC provider's rate limits

### WebSocket Required
The indexer uses `SubscribeNewHead` for real-time block monitoring. HTTP-only RPC endpoints will not work.

### RPC Provider Recommendations
- **Alchemy** (recommended): Higher rate limits, WebSocket support
- **Infura**: Reliable, WebSocket support
- **QuickNode**: Fast, dedicated nodes available
- **Local Anvil/Geth**: Best for development, no rate limits

### Error Handling
The indexer automatically retries on RPC connection failures, rate limit errors (with exponential backoff), and temporary storage issues. Fatal errors requiring intervention: invalid ABI configuration, unrecoverable storage failures, WebSocket subscription failures.

## License

MIT

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request
