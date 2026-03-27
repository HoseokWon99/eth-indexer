# API Reference

This system exposes three HTTP services: **API Server** (query interface), **Indexer** (state introspection), and **Dashboard** (UI + real-time SSE stream).

---

# API Server

Base path: `/api`

Exposes a read-only HTTP interface for querying indexed Ethereum event records stored in PostgreSQL. Responses are cached in Redis.

---

## Endpoints

### GET /api/health

Returns the service health status.

**Response**

- `200 OK` — service is healthy; body is the plain text string `OK`
- `500 Internal Server Error` — service is unhealthy

---

### GET /api/search/{topic}

Search indexed Ethereum event records for a given event topic.

**Path Parameter**

| Parameter | Type   | Description                                                                                                    |
|-----------|--------|----------------------------------------------------------------------------------------------------------------|
| `topic`   | string | Event topic name (e.g., `Transfer`, `Swap`). Must match one of the topics configured via the `TOPICS` env var. |

**Status Codes**

| Code | Meaning                                            |
|------|----------------------------------------------------|
| 200  | Success                                            |
| 400  | Invalid query parameter value or format            |
| 404  | Topic not found (not registered in `TOPICS`)       |
| 405  | Method not allowed                                 |
| 500  | Internal server error                              |

---

## Query Parameters

All query parameters are optional.

| Parameter          | Type                    | Description                                                                                       |
|--------------------|-------------------------|---------------------------------------------------------------------------------------------------|
| `contract_address` | comma-separated strings | Filter by one or more contract addresses                                                          |
| `tx_hash`          | comma-separated strings | Filter by one or more transaction hashes                                                          |
| `block_hash`       | comma-separated strings | Filter by one or more block hashes                                                                |
| `block_number`     | JSON ComparisonFilter   | Numeric comparison on block number. Supported operators: `lt`, `lte`, `gt`, `gte`, `eq`          |
| `log_index`        | comma-separated uint64  | Filter by one or more log index positions                                                         |
| `data`             | JSON object             | JSONB containment filter on decoded event parameters                                              |
| `timestamp`        | JSON ComparisonFilter   | Time comparison on event timestamp (RFC3339). Supported operators: `lt`, `lte`, `gt`, `gte`, `eq` |
| `cursor`           | JSON object             | Pagination cursor: `{"block_number": <uint64>, "log_index": <uint64>}`                           |
| `limit`            | uint64                  | Maximum number of records to return                                                               |

### ComparisonFilter Format

`block_number` and `timestamp` accept a JSON object with one or more comparison operators.

```json
{"gte": 19000000, "lt": 19001000}
```

For `block_number`, values are unsigned integers. For `timestamp`, values are RFC3339 strings.

---

## Response

### SearchResponse

```json
{
  "count": 2,
  "result": [
    {
      "contract_address": "0x...",
      "tx_hash": "0x...",
      "block_hash": "0x...",
      "block_number": 12345,
      "log_index": 0,
      "data": {
        "from": "0x...",
        "to": "0x...",
        "value": "1000000000000000000"
      },
      "timestamp": "2024-01-01T00:00:00Z"
    }
  ]
}
```

| Field    | Type    | Description                                 |
|----------|---------|---------------------------------------------|
| `count`  | integer | Number of records returned in this response |
| `result` | array   | Array of event records                      |

**EventRecord fields**

| Field              | Type    | Description                                          |
|--------------------|---------|------------------------------------------------------|
| `contract_address` | string  | Address of the smart contract that emitted the event |
| `tx_hash`          | string  | Transaction hash                                     |
| `block_hash`       | string  | Block hash                                           |
| `block_number`     | uint64  | Block number                                         |
| `log_index`        | uint64  | Log index within the block                           |
| `data`             | object  | Decoded event parameters (structure varies by event) |
| `timestamp`        | string  | Block timestamp in RFC3339 format                    |

---

## Pagination

Pagination uses a cursor based on the last record in the current page.

- Results are ordered by `block_number ASC, log_index ASC`.
- To fetch the next page, pass the `block_number` and `log_index` of the last record as the `cursor` parameter.

```
cursor={"block_number": 19000500, "log_index": 5}
```

---

## Caching

Responses are cached in Redis. The cache key is derived from the topic name and the full query string. Cache TTL is configured via the `API_TTL` environment variable (default: `60` seconds).

---

## Configuration

| Variable             | Default | Required | Description                                          |
|----------------------|---------|----------|------------------------------------------------------|
| `API_PORT`           | `8080`  | No       | Server listening port                                |
| `API_TTL`            | `60`    | No       | Redis cache TTL in seconds                           |
| `TOPICS`             |         | Yes      | Comma-separated list of registered event topic names |
| `REDIS_HOST`         |         | Yes      | Redis hostname                                       |
| `REDIS_PORT`         | `6379`  | No       | Redis port                                           |
| `REDIS_PASSWORD`     |         | No       | Redis password                                       |
| `REDIS_DB`           | `0`     | No       | Redis database number                                |
| `REDIS_CA_CERT_PATH` |         | No       | Path to TLS CA certificate for Redis                 |
| `POSTGRES_HOST`      |         | Yes      | PostgreSQL host                                      |
| `POSTGRES_PORT`      | `5432`  | No       | PostgreSQL port                                      |
| `POSTGRES_USER`      |         | Yes      | PostgreSQL user                                      |
| `POSTGRES_PASSWORD`  |         | Yes      | PostgreSQL password                                  |
| `POSTGRES_DB`        |         | Yes      | PostgreSQL database name                             |

---

## Examples

**Health check**

```
GET /api/health
```

**Filter by contract address with a result limit**

```
GET /api/search/Transfer?contract_address=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48&limit=10
```

**Filter by block number range**

```
GET /api/search/Swap?block_number={"gte":19000000,"lt":19001000}&limit=50
```

**Filter by decoded event data and timestamp**

```
GET /api/search/Approval?data={"spender":"0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"}&timestamp={"gte":"2024-01-01T00:00:00Z"}
```

**Paginate using a cursor**

```
GET /api/search/Transfer?cursor={"block_number":19000500,"log_index":5}&limit=25
```

---

# Indexer Service

Base path: `/indexer`

Exposes a minimal HTTP interface for liveness and state introspection.

## Endpoints

### GET /indexer/health

Returns the service health status.

**Response**

- `200 OK` — service is healthy (empty body)

---

### GET /indexer/state

Returns the last indexed block number for each configured event topic.

**Response**

```json
{
  "Transfer": 19000500,
  "Approval": 19000480
}
```

| Field | Type   | Description                                           |
|-------|--------|-------------------------------------------------------|
| key   | string | Event topic name                                      |
| value | uint64 | Last block number successfully indexed for that topic |

**Status Codes**

| Code | Meaning               |
|------|-----------------------|
| 200  | Success               |
| 500  | Internal server error |

## Configuration

| Variable       | Default | Required | Description           |
|----------------|---------|----------|-----------------------|
| `INDEXER_PORT` | `8080`  | No       | Server listening port |

---

# Dashboard Service

Base path: `/dashboard`

Serves the frontend UI and provides configuration and a real-time Server-Sent Events (SSE) stream of Debezium CDC events from Kafka.

## Endpoints

### GET /dashboard/health

Returns the service health status.

**Response**

- `200 OK` — service is healthy (empty body)

---

### GET /dashboard/config

Returns dashboard runtime configuration.

**Response**

```json
{
  "topics": ["Transfer", "Approval"],
  "apiServerUrl": "http://api-server:8080"
}
```

| Field          | Type     | Description                                     |
|----------------|----------|-------------------------------------------------|
| `topics`       | string[] | List of registered event topic names            |
| `apiServerUrl` | string   | Base URL of the API Server used by the frontend |

**Status Codes**

| Code | Meaning               |
|------|-----------------------|
| 200  | Success               |
| 500  | Internal server error |

---

### GET /dashboard/events

Streams real-time Debezium CDC events from Kafka as a Server-Sent Events (SSE) stream.

**Response Headers**

```
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive
Access-Control-Allow-Origin: *
```

**Stream Format**

Each event is a line of the form:

```
data: <json>\n\n
```

The JSON payload is the raw Debezium CDC message from Kafka. Each message contains at minimum a `topic` field identifying the event type.

**Behavior**

- Connection is kept open indefinitely.
- Per-client buffer of 64 messages; messages are dropped on overflow.
- Stream ends when the client disconnects.

**Status Codes**

| Code | Meaning               |
|------|-----------------------|
| 200  | Stream started        |
| 500  | Internal server error |

---

### GET /dashboard/

Serves the embedded static frontend assets (HTML, JS, CSS).

## Configuration

| Variable             | Default | Required | Description                                               |
|----------------------|---------|----------|-----------------------------------------------------------|
| `DASHBOARD_PORT`     | `8080`  | No       | Server listening port                                     |
| `TOPICS`             |         | Yes      | Comma-separated list of registered event topic names      |
| `API_SERVER_URL`     |         | Yes      | URL of the API Server passed to the frontend via /config  |
| `KAFKA_BROKERS`      |         | Yes      | Comma-separated Kafka broker addresses                    |
| `KAFKA_SOURCE_TOPIC` |         | Yes      | Kafka topic to consume CDC events from                    |
