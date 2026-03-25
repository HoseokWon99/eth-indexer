# Monitoring Stack

All monitoring components run in the `eth-indexer` namespace alongside application services.

- **kafka-exporter** (`danielqsj/kafka-exporter`) — scrapes Kafka broker at `kafka:9092`, exposes metrics on `:9308`
- **Prometheus** (`prom/prometheus`) — scrapes `kafka-exporter:9308` every 15s; 7-day retention
- **Grafana** (`grafana/grafana`) — pre-provisioned with Prometheus datasource and the ETH Indexer dashboard
  - Dashboard panels: event ingestion rate, total records by event type, events in last 5 min, consumer lag, broker count, total CDC events captured
  - Access: `http://localhost:3000` via port-forward; credentials from `grafana-credentials` Secret

Source configs in `monitoring/` are used by Docker Compose. The k8s equivalents live in `k8s/monitoring/` as ConfigMaps.
