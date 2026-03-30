# Architecture

## Indexing Pipeline

```
Ethereum RPC (WebSocket)
→ Indexer.Run (SubscribeNewHead)
→ indexAll() — fans out to all scanners concurrently (one goroutine per scanner)
→ EventRecordsScanner.Scan (FilterLogs + ABI decode)
→ MongoEventRecordsStorage.SaveAll (bulk upsert, $setOnInsert — idempotent)
→ SimpleStateStorage.SetLastBlockNumber (in-memory; flushed to JSON file on close)
```

## Query Pipeline

```
HTTP Client
→ GET /search/{topic}
→ Handler.Search (cache-aside)
  → Redis hit  → return cached result
  → Redis miss → MongoDB query → write cache
→ JSON response
```

## CDC / Monitoring Pipeline
```
MongoDB (change streams)
→ Debezium (Kafka Connect) — CDC via MongoDB connector
→ Kafka topic: eth-indexer.eth_indexer.event_records
→ Kafka Router — routes to eth-indexer.events.{eventType}
→ kafka-exporter — exposes Kafka metrics to Prometheus
→ Prometheus — scrapes kafka-exporter:9308
→ Grafana — visualizes event ingestion rate, consumer lag, totals
```
