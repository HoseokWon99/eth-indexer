# eth-indexer

A production-grade Ethereum event indexer that captures smart contract events and stores them in OpenSearch for fast, structured querying.

## Features

- ✅ **Deterministic indexing** - Replaying blocks produces identical results
- ✅ **Idempotent operations** - Document IDs are deterministic (blockHash-txHash-logIndex)
- ✅ **Reorg-safe** - Only indexes confirmed blocks
- ✅ **High throughput** - Bulk insertion with configurable batching
- ✅ **Search API** - RESTful API for querying indexed events
- ✅ **Resumable** - Tracks last indexed block, safe to restart
- ✅ **Docker-ready** - Complete containerization support

## Quick Start

### Using Docker Compose

1. Copy the example environment file:
```bash
cp .env.example .env
```

2. Edit `.env` with your configuration:
```bash
# Required settings
RPC_URL=https://mainnet.infura.io/v3/YOUR_PROJECT_ID
CONTRACT_ADDRESSES=0x1234...
EVENT_NAME=Transfer
ABI_PATH=/abi/contract.abi.json
```

3. Place your contract ABI in `./abi/contract.abi.json`

4. Start the services:
```bash
docker-compose up -d
```

### Using Go

1. Install dependencies:
```bash
go mod download
```

2. Set environment variables:
```bash
export RPC_URL=https://mainnet.infura.io/v3/YOUR_PROJECT_ID
export CONTRACT_ADDRESSES=0x1234...
export EVENT_NAME=Transfer
export ABI_PATH=/path/to/contract.abi.json
export OPENSEARCH_URL=http://localhost:9200
```

3. Run the indexer:
```bash
make run
# or
go run ./cmd/eth-core
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RPC_URL` | Yes | - | Ethereum RPC endpoint |
| `CONTRACT_ADDRESSES` | Yes | - | Comma-separated contract addresses |
| `EVENT_NAME` | Yes | - | Event name to index (must exist in ABI) |
| `ABI_PATH` | Yes | - | Path to contract ABI JSON file |
| `OPENSEARCH_URL` | No | `http://localhost:9200` | OpenSearch endpoint |
| `CONFIRMED_AFTER` | No | `12` | Blocks to wait before indexing |
| `START_BLOCK` | No | `0` | Starting block number |
| `POLL_INTERVAL` | No | `12s` | Block polling interval |
| `API_PORT` | No | `8080` | API server port |

## API Endpoints

### Health Check
```bash
GET /health
```

Response:
```json
{"status": "ok"}
```

### Indexer Status
```bash
GET /status
```

Response:
```json
{
  "last_block": 18500000,
  "event": "Transfer"
}
```

### Search Events
```bash
POST /search
Content-Type: application/json
```

Request body:
```json
{
  "contract_address": ["0x1234..."],
  "block_number": {
    "gte": 18000000,
    "lte": 18500000
  },
  "tx_hash": ["0xabcd..."]
}
```

Response:
```json
{
  "total": 150,
  "records": [
    {
      "contract_address": "0x1234...",
      "tx_hash": "0xabcd...",
      "block_hash": "0xefgh...",
      "block_number": 18123456,
      "log_index": 5,
      "data": {
        "from": "0x...",
        "to": "0x...",
        "value": "1000000000000000000"
      },
      "timestamp": "2024-01-15T10:30:00Z"
    }
  ]
}
```

### Filter Options

- **contract_address**: Array of contract addresses
- **tx_hash**: Array of transaction hashes
- **block_hash**: Array of block hashes
- **log_index**: Array of log indices
- **block_number**: Comparison filter (`lt`, `lte`, `gt`, `gte`, `eq`)
- **timestamp**: Comparison filter
- **data**: Nested field filters (event-specific)

Example with comparison filters:
```json
{
  "block_number": {
    "gte": 18000000,
    "lt": 18100000
  },
  "timestamp": {
    "gte": "2024-01-01T00:00:00Z"
  }
}
```

## Architecture

```
Ethereum RPC
    ↓
Log Filtering (topic0 + contracts)
    ↓
ABI Decoding
    ↓
Data Normalization
    ↓
OpenSearch Bulk Insert
    ↓
Query API
```

## Document ID Format

Documents are stored with deterministic IDs to ensure idempotency:

```
{txHash}-{blockNumber}
```

This prevents duplicate indexing and allows safe re-indexing of blocks.

## Development

### Build
```bash
make build
# or
go build -o bin/eth-core ./cmd/eth-core
```

### Run Tests
```bash
go test ./...
```

### Docker Build
```bash
docker build -t eth-core:latest .
```

## Production Considerations

1. **Confirmation Depth**: Set `CONFIRMED_AFTER` based on your chain's finality (12+ for Ethereum mainnet)
2. **Poll Interval**: Adjust based on block time (12s for Ethereum, faster for L2s)
3. **OpenSearch Tuning**: Configure shards/replicas based on data volume
4. **Error Handling**: Monitor logs for RPC failures and indexing errors
5. **Backfilling**: Start with a recent `START_BLOCK` and backfill separately if needed

## License

MIT
