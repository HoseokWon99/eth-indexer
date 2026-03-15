# eth-indexer

This service indexes specific Ethereum smart contract events and stores them in OpenSearch for fast, structured querying.

## Skills
- Languages: Go
- Libraries: go-ethereum, opensearch-go
- Storage: OpenSearch, Redis(Cache)
- Deployment: Docker

## What It Does

- Connects to Ethereum via RPC
- Filters logs by contract + event (topic0)
- Decodes ABI-encoded data
- Normalizes values for storage
- Bulk inserts records into Postgres
- Exposes search API

## Key Design Principles

- **Deterministic** — replaying blocks produces identical results
- **Idempotent** — document IDs are deterministic (blockHash-txHash-logIndex)
- **Reorg-safe** — only indexes blocks after `confirmedAfter`
- **Search-optimized** — data structured for efficient filtering and pagination

## Data Flow

Ethereum RPC  
→ Log Filtering  
→ ABI Decoding  
→ Normalization  
→ OpenSearch Bulk Insert  
→ Query API

## Storage Strategy

- Deterministic document ID:

  `blockHash-txHash-logIndex`

- Confirmed-only indexing:

  `safeBlock = latest - confirmedAfter`

- Immutable documents (no rollback required)

## Query Layer

- Accepts validated QueryDSL-style filters
- Uses OpenSearch `_search`
- Uses `search_after` for scalable pagination

## Operational Characteristics

- Resume-safe via persisted block state
- Bulk ingestion for high throughput
- Horizontally scalable
- Suitable for high-volume EVM chains

---

This system provides a reliable, production-grade pipeline for indexing and querying Ethereum event data at scale.