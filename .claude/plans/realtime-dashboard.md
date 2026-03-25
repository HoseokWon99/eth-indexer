# Plan: Realtime Event Dashboard — Extend `services/dashboard`

## Goal

Extend `services/dashboard` to also serve a web UI that streams indexed Ethereum event records to the browser in realtime, grouped by topic.

Currently `dashboard` is a pure Kafka router (CDC fan-out). The plan adds an SSE HTTP server alongside the existing routing loop.

## Current State

```
PostgreSQL (WAL)
  → Debezium → Kafka: eth-indexer.public.event_records
    → dashboard/main.go (fan-out router)
      → Kafka: eth-indexer.events.Transfer
      → Kafka: eth-indexer.events.Approval
      → ...
```

The router already splits events by topic into per-event Kafka topics.

## Target State

```
Kafka: eth-indexer.events.Transfer
Kafka: eth-indexer.events.Approval
  → dashboard SSE hub
    → Browser (EventSource API → live table per topic tab)
```

The dashboard service:
1. Continues to run the existing CDC fan-out router (unchanged)
2. Additionally subscribes to each `eth-indexer.events.*` topic as a consumer
3. Forwards messages to an in-process SSE hub
4. Serves the web UI and SSE endpoint over HTTP

## Architecture Decisions

| Decision | Choice | Reason |
|---|---|---|
| Transport | SSE (not WebSocket) | Unidirectional; plain HTTP; works through existing Gateway; no upgrade |
| Frontend | Vanilla HTML/JS via `go:embed` | No npm/Node in Docker; binary stays small |
| Extend `dashboard` vs new service | Extend `dashboard` | It already owns the Kafka event pipeline; adding HTTP is additive |
| Replicas | 1 (already constrained) | Consumer group ordering; SSE hub is in-process |

## Changes to `services/dashboard/`

### New files

```
services/dashboard/
  sse/
    hub.go        ← client registry + broadcast loop
    handler.go    ← HTTP handler (text/event-stream)
  api/
    server.go     ← GET /health, /config, /events, / (static)
  consumer/
    consumer.go   ← subscribes to eth-indexer.events.* topics, fans into hub
  static/
    index.html    ← EventSource + backfill fetch, topic tabs, live table
```

### Modified files

- `main.go` — wire up new consumer, SSE hub, and HTTP server alongside existing router loop
- `go.mod` — no new deps (already has `kafka-go`; stdlib covers `net/http` and `embed`)

## Component Details

### Consumer (`consumer/consumer.go`)

- One `kafka.NewReader` per configured topic (from `TOPICS` env var)
- Each reader runs in its own goroutine, fans messages into `chan Message`
- `Message` carries raw JSON bytes + topic name
- GroupID: `eth-event-ui` (separate from the existing `eth-event-router` group)
- Messages on `eth-indexer.events.*` are already plain row JSON (router re-publishes `msg.Value` unchanged)

### SSE Hub (`sse/hub.go`)

```
type Client struct {
    topic string       // empty = all topics
    ch    chan []byte  // buffered (64); full = drop + log
}

Hub.Run() goroutine selects on: register / unregister / broadcast
```

### SSE Handler (`sse/handler.go`)

- `GET /events?topic={name}` — streams `data: {...}\n\n`
- Sets `Content-Type: text/event-stream`, `Cache-Control: no-cache`
- Registers/deregisters client via `r.Context().Done()`

### HTTP Server (`api/server.go`)

| Route | Response |
|---|---|
| `GET /health` | `200 OK` |
| `GET /config` | JSON: `{"topics": [...], "apiServerUrl": "..."}` |
| `GET /events` | SSE stream (query param: `topic`) |
| `GET /` | Embedded `index.html` |

Graceful shutdown on SIGTERM/SIGINT (same signal context as the router).

### Static UI (`static/index.html`)

- Topic tabs from `GET /config`
- `<table>` columns: Time, Block, TxHash (truncated), Contract, Topic, Data (collapsed JSON)
- `EventSource` on `/events?topic={activeTab}`; auto-reconnects
- Tab switch: close EventSource, open new one, clear table, fetch backfill from api-server
- New rows flash green for 2s via CSS transition
- ~200 lines, zero JS dependencies

## Config (new env vars)

| Var | Default | Description |
|---|---|---|
| `UI_PORT` | `8090` | HTTP listen port |
| `TOPICS` | `Transfer,Approval` | Comma-separated topic names to consume and expose |
| `API_SERVER_URL` | `http://api-server` | Passed to browser for backfill fetch |

Existing env vars (`KAFKA_BOOTSTRAP_SERVERS`, `SOURCE_TOPIC`, `DEST_TOPIC_PREFIX`) are unchanged.

## Wire Message Format

Raw bytes forwarded from Kafka → SSE → `JSON.parse` in browser:

```json
{
  "topic": "Transfer",
  "contract_address": "0x...",
  "tx_hash": "0x...",
  "block_hash": "0x...",
  "block_number": 21000000,
  "log_index": 3,
  "data": {"from": "0x...", "to": "0x...", "value": "1000"},
  "timestamp": "2026-03-25T12:00:00Z"
}
```

## K8s Changes

### `k8s/dashboard/deployment.yaml`

Add new env vars and expose HTTP port:

```yaml
env:
  - name: UI_PORT
    value: "8090"
  - name: TOPICS
    value: "Transfer,Approval"
  - name: API_SERVER_URL
    value: "http://api-server"
ports:
  - containerPort: 8090
readinessProbe:
  httpGet:
    path: /health
    port: 8090
```

### New `k8s/dashboard/service.yaml`

ClusterIP service, port 80 → targetPort 8090.

### `k8s/gateway.yaml`

Add `/dashboard` HTTPRoute rule → `dashboard` service, URLRewrite to strip prefix.

## Docker Compose Changes

Add env vars and port to existing `dashboard:` service block:

```yaml
environment:
  UI_PORT: "8090"
  TOPICS: "Transfer,Approval"
  API_SERVER_URL: "http://api-server:8080"
ports:
  - "${DASHBOARD_PORT:-8090}:8090"
```

## Reference Files

- `services/dashboard/main.go` — existing router loop to keep intact; new code runs alongside it
- `services/api-server/api/server.go` — HTTP server + graceful shutdown pattern
- `k8s/gateway.yaml` — URLRewrite filter pattern to extend