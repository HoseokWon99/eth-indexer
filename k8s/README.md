# Kubernetes Deployment Guide

This guide covers the Kubernetes configuration for `eth-indexer` and how to deploy it to a cluster.

## Overview

All manifests live in `k8s/` and target the `eth-indexer` namespace.

```
k8s/
  namespace.yaml
  secrets.yaml
  gateway.yaml
  external-services.yaml      ExternalName services: postgres, valkey, kafka, eth-rpc
  kafka-connect/              deployment.yaml, service.yaml, debezium-configmap.yaml, debezium-init-job.yaml
  dashboard/               deployment.yaml
  indexer/                    configmap.yaml, deployment.yaml
  api-server/                 deployment.yaml, service.yaml
  monitoring/
    kafka-exporter/           deployment.yaml, service.yaml
    prometheus/               configmap.yaml, deployment.yaml, service.yaml
    grafana/                  configmap.yaml, deployment.yaml, service.yaml
```

> **External infrastructure** — PostgreSQL, Valkey, Kafka, and the Ethereum RPC node are expected to run **outside** the cluster. `external-services.yaml` registers them as `ExternalName` services so in-cluster workloads can reach them by a stable DNS name.

### Architecture

```
                                  ┌──────────────────────────────────────────────────────┐
                                  │                eth-indexer (ns)                      │
                                  │                                                      │
  Ethereum RPC (external)         │  Indexer (1 replica)                                 │
  ────────────────────────────────►  └─► PostgreSQL (ExternalName → external host)       │
                                  │        └─► Debezium (Kafka Connect)                  │
  HTTP Client                     │               └─► Kafka (ExternalName → external)    │
  ──► Nginx Ingress /api          ►  API Server (2 replicas)                             │
  ──► Nginx Ingress /indexer/state►  └─► PostgreSQL (read)                              │
                                  │  └─► Valkey (ExternalName → external host, cache)    │
                                  │                                                      │
                                  │  Kafka Router ◄─── Kafka CDC topic                  │
                                  │                                                      │
                                  │  Monitoring                                          │
  ──► Nginx Ingress /grafana      ►  Grafana ◄── Prometheus ◄── kafka-exporter ◄── Kafka │
                                  └──────────────────────────────────────────────────────┘
```

---

## Exposed Ports

### In-cluster Services

| Service | Container Port | Service Port | Protocol | Description |
|---|---|---|---|---|
| `api-server` | 8080 | 80 | HTTP | REST query API |
| `kafka-connect` | 8083 | 8083 | HTTP | Debezium Connect REST API |
| `kafka-exporter` | 9308 | 9308 | HTTP | Prometheus metrics for Kafka |
| `prometheus` | 9090 | 9090 | HTTP | Metrics scrape & query |
| `grafana` | 3000 | 3000 | HTTP | Dashboard UI |

### External Services (ExternalName — point outside the cluster)

| Service | Port | Description |
|---|---|---|
| `postgres` | 5432 | PostgreSQL database |
| `valkey` | 6379 | Valkey (Redis-compatible) cache |
| `kafka` | 9092 | Kafka broker |
| `eth-rpc` | 8545 | Ethereum JSON-RPC / WebSocket |

### Ingress (public-facing, all via `${GATEWAY_HOST}`)

| Path | Backend Service | Backend Port | Description |
|---|---|---|---|
| `/api` | `api-server` | 80 | Event search API |
| `/indexer/state` | `indexer` | 80 | Indexer state endpoint |
| `/grafana` | `grafana` | 3000 | Grafana dashboard |

### Port-forward (local development access)

```bash
kubectl port-forward -n eth-indexer svc/api-server    8080:80
kubectl port-forward -n eth-indexer svc/grafana       3000:3000
kubectl port-forward -n eth-indexer svc/prometheus    9090:9090
kubectl port-forward -n eth-indexer svc/kafka-connect 8083:8083
```

---

## Prerequisites

### 1. Nginx Ingress Controller

`cluster-up.sh` enables the minikube ingress addon automatically. For a non-minikube cluster, install once per cluster:

```bash
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

### 2. External Infrastructure

Ensure PostgreSQL, Valkey, Kafka, and your Ethereum RPC node are reachable from the cluster. Their hostnames are injected via the environment variables below.

### 3. Docker Images

Build and push all three images to your registry:

```bash
make docker-build

docker tag eth-indexer      your-registry/eth-indexer:latest
docker tag eth-api-server   your-registry/eth-api-server:latest
docker tag eth-dashboard your-registry/eth-dashboard:latest

docker push your-registry/eth-indexer:latest
docker push your-registry/eth-api-server:latest
docker push your-registry/eth-dashboard:latest
```

Then update the `image:` fields in:
- `k8s/indexer/deployment.yaml`
- `k8s/api-server/deployment.yaml`
- `k8s/dashboard/deployment.yaml`

---

## Configuration

### Environment Variables

The following variables must be set before applying manifests (or placed in a `.env` file when using `cluster-up.sh`):

| Variable | Description |
|---|---|
| `POSTGRES_USER` | PostgreSQL username |
| `POSTGRES_PASSWORD` | PostgreSQL password |
| `POSTGRES_DB` | PostgreSQL database name |
| `POSTGRES_HOST` | External PostgreSQL hostname (used in `external-services.yaml`) |
| `REDIS_PASSWORD` | Valkey/Redis password (can be empty) |
| `REDIS_HOST` | External Valkey hostname |
| `KAFKA_HOST` | External Kafka hostname |
| `RPC_HOST` | External Ethereum RPC hostname |
| `GRAFANA_ADMIN_USER` | Grafana admin username |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password |
| `GATEWAY_HOST` | Public hostname for the Nginx Ingress (e.g. `eth-indexer.example.com`) |

### Secrets (`k8s/secrets.yaml`)

Applied via `envsubst` to interpolate the env vars above. Do not commit real credentials.

| Secret | Keys |
|---|---|
| `postgres-credentials` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` |
| `valkey-credentials` | `REDIS_PASSWORD` |
| `grafana-credentials` | `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD` |

For production, use `kubectl create secret` or a secrets manager (AWS Secrets Manager, Vault) instead of the template file.

### Indexer Config (`k8s/indexer/configmap.yaml`)

The ConfigMap is created from a JSON file passed to `cluster-up.sh`. Update the file to match your deployment:

| Field | Default | Description |
|---|---|---|
| `contract_addresses` | USDC + USDT on mainnet | Contracts to watch |
| `event_names` | `["Transfer", "Approval"]` | Events to index |
| `abi` | ERC-20 Transfer + Approval | ABI for the events above |
| `confirmed_after` | `12` | Blocks to wait before indexing (reorg safety) |
| `offset_block_number` | `0` | Starting block (0 = genesis) |

### API Server (`k8s/api-server/deployment.yaml`)

| Env Var | Default | Description |
|---|---|---|
| `TOPICS` | `Transfer,Approval` | Comma-separated list of allowed query topics |
| `API_TTL` | `60` | Redis cache TTL in seconds |
| `API_PORT` | `8080` | Listening port |

### Ingress (`k8s/gateway.yaml`)

Set the `GATEWAY_HOST` env var before running `envsubst`. Paths routed:
- `/api` → `api-server:80`
- `/indexer/state` → `indexer:80`
- `/grafana` → `grafana:3000`

---

## Deploy

### Automated (minikube)

```bash
scripts/k8s/cluster-up.sh <path-to-indexer-indexer.json>
```

Requires all env vars above to be exported or present in `.env`. The script:
1. Starts a minikube cluster (`eth-indexer`, 4 CPUs, 6 GB RAM)
2. Enables the ingress addon
3. Builds all three Docker images inside minikube's daemon
4. Applies all manifests in the correct order

### Manual (any cluster)

Apply resources in dependency order:

```bash
# 1. Namespace
kubectl apply -f k8s/namespace.yaml

# 2. Secrets and external service mappings
envsubst < k8s/secrets.yaml          | kubectl apply -f -
envsubst < k8s/external-services.yaml | kubectl apply -f -

# 3. Kafka Connect + Debezium connector registration
kubectl apply -f k8s/kafka-connect/

# 4. Application services (indexer indexer created from file)
kubectl create configmap indexer-indexer \
  --from-file=indexer-indexer.json=<path-to-indexer-indexer.json> \
  -n eth-indexer --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/indexer/deployment.yaml
kubectl apply -f k8s/api-server/
kubectl apply -f k8s/dashboard/

# 5. Ingress
envsubst < k8s/gateway.yaml | kubectl apply -f -

# 6. Monitoring stack
kubectl apply -f k8s/monitoring/grafana/
kubectl apply -f k8s/monitoring/kafka-exporter/
kubectl apply -f k8s/monitoring/prometheus/
```

---

## Resource Reference

### External Services — `external-services.yaml`

| Service Name | Type | External Host Var | Port |
|---|---|---|---|
| `postgres` | ExternalName | `${POSTGRES_HOST}` | 5432 |
| `valkey` | ExternalName | `${REDIS_HOST}` | 6379 |
| `kafka` | ExternalName | `${KAFKA_HOST}` | 9092 |
| `eth-rpc` | ExternalName | `${RPC_HOST}` | 8545 |

### Kafka Connect — Deployment + Service

| Property | Value |
|---|---|
| Image | `debezium/connect:2.6` |
| Replicas | 1 |
| Port | 8083 (REST API) |
| Bootstrap | `kafka:9093` |
| Group ID | `eth-indexer-connect` |

The `debezium-init-job.yaml` Job runs once to register the PostgreSQL CDC connector. It waits for Kafka Connect to be ready, then calls the REST API. It self-deletes 300 seconds after completion.

### Indexer — Deployment

| Property | Value |
|---|---|
| Image | `eth-indexer:latest` |
| Replicas | **1 (fixed)** — must not run concurrently |
| Config | Mounted from `indexer-config` ConfigMap at `/etc/eth-indexer/` |
| State file | Persisted to 1 Gi PVC at `/var/lib/eth-indexer/state/` |
| Init container | Waits for `postgres:5432` |

### API Server — Deployment + Service

| Property | Value |
|---|---|
| Image | `eth-api-server:latest` |
| Replicas | 2 (horizontally scalable) |
| Port | 8080 → Service port 80 |
| Health check | `GET /health` |
| Init containers | Waits for `postgres:5432` and `valkey:6379` |

### Kafka Router — Deployment

| Property | Value |
|---|---|
| Image | `eth-dashboard:latest` |
| Replicas | **1 (fixed)** — single consumer group member |
| Source topic | `eth-indexer.public.event_records` (Debezium CDC) |
| Dest prefix | `eth-indexer.events.{eventType}` |
| Init container | Waits for `kafka:9092` |

### Kafka Exporter — Deployment + Service

| Property | Value |
|---|---|
| Image | `danielqsj/kafka-exporter:latest` |
| Replicas | 1 |
| Scrapes | `kafka:9092` |
| Metrics port | 9308 |
| Init container | Waits for `kafka:9092` |

### Prometheus — Deployment + Service

| Property | Value |
|---|---|
| Image | `prom/prometheus:latest` |
| Replicas | 1 |
| Port | 9090 |
| Retention | 7 days |
| Scrapes | `kafka-exporter:9308` every 15 s |
| Config | Mounted from `prometheus-config` ConfigMap |

### Grafana — Deployment + Service

| Property | Value |
|---|---|
| Image | `grafana/grafana:latest` |
| Replicas | 1 |
| Port | 3000 |
| Credentials | From `grafana-credentials` Secret |
| Datasource | Prometheus (pre-provisioned) |
| Dashboard | ETH Indexer (event rate, consumer lag, record totals) |

### Ingress

| Property | Value |
|---|---|
| Class | `nginx` |
| Proxy read timeout | 60 s |
| Proxy send timeout | 60 s |
| Max body size | 1 m |

---

## Operations

### View logs

```bash
kubectl logs -n eth-indexer -l app=indexer       -f
kubectl logs -n eth-indexer -l app=api-server    -f
kubectl logs -n eth-indexer -l app=dashboard  -f
```

### Check pod status

```bash
kubectl get pods -n eth-indexer
```

### Port-forward for local access

```bash
# API server
kubectl port-forward -n eth-indexer svc/api-server 8080:80

# Grafana dashboard
kubectl port-forward -n eth-indexer svc/grafana 3000:3000

# Prometheus
kubectl port-forward -n eth-indexer svc/prometheus 9090:9090

# Kafka Connect REST API
kubectl port-forward -n eth-indexer svc/kafka-connect 8083:8083
```

### Update indexer config

```bash
kubectl create configmap indexer-indexer \
  --from-file=indexer-indexer.json=<path-to-new-indexer.json> \
  -n eth-indexer --dry-run=client -o yaml | kubectl apply -f -
# Restart indexer to pick up changes:
kubectl rollout restart deployment/indexer -n eth-indexer
```

### Scale API server

```bash
kubectl scale deployment api-server --replicas=4 -n eth-indexer
```

### Tear down

```bash
# minikube
scripts/k8s/cluster-down.sh

# or manually
kubectl delete namespace eth-indexer
```

> **Note:** Deleting the namespace also removes the `indexer-state` PVC and its data. The external PostgreSQL, Valkey, and Kafka instances are unaffected.
