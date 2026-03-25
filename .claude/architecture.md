# Architecture

## Indexing Pipeline

```
Ethereum RPC (WebSocket)
→ Indexer.Run (SubscribeNewHead)
→ indexAll() — fans out to all scanners concurrently (one goroutine per scanner)
→ EventRecordsScanner.Scan (FilterLogs + ABI decode)
→ PostgresEventRecordsStorage.SaveAll (bulk insert, ON CONFLICT DO NOTHING)
→ SimpleStateStorage.SetLastBlockNumber (in-memory; flushed to JSON file on close)
```

## Query Pipeline

```
HTTP Client
→ GET /search/{topic}
→ Handler.Search (cache-aside)
  → Redis hit  → return cached result
  → Redis miss → PostgreSQL query → write cache
→ JSON response
```

## CDC / Monitoring Pipeline

```
PostgreSQL (WAL)
→ Debezium (Kafka Connect) — CDC via pgoutput plugin
→ Kafka topic: eth-indexer.public.event_records
→ Kafka Router — routes to eth-indexer.events.{eventType}
→ kafka-exporter — exposes Kafka metrics to Prometheus
→ Prometheus — scrapes kafka-exporter:9308
→ Grafana — visualizes event ingestion rate, consumer lag, totals
```
