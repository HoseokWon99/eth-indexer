# Kubernetes Deployment

## Secrets (`k8s/secrets.yaml`)

| Secret | Keys |
|---|---|
| `postgres-credentials` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` |
| `valkey-credentials` | `REDIS_PASSWORD` |
| `rpc-credentials` | `RPC_URL` |
| `grafana-credentials` | `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD` |

## Cluster Scripts

```bash
# Start minikube cluster, build images, apply all manifests
scripts/k8s/cluster-up.sh

# Tear down cluster
scripts/k8s/cluster-down.sh
```

`cluster-up.sh` requires these env vars (or a `.env` file):
`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `REDIS_PASSWORD`, `RPC_URL`, `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD`, `GATEWAY_HOST`, `POSTGRES_HOST`, `REDIS_HOST`, `KAFKA_HOST`

## Apply Order (manual)

```bash
kubectl apply -f k8s/namespace.yaml
envsubst < k8s/secrets.yaml | kubectl apply -f -
envsubst < k8s/external-services.yaml | kubectl apply -f -
kubectl apply -f k8s/kafka-connect/
kubectl apply -f k8s/indexer/ && kubectl apply -f k8s/api-server/ && kubectl apply -f k8s/dashboard/
envsubst < k8s/gateway.yaml | kubectl apply -f -
kubectl apply -f k8s/monitoring/
```

## Port-forwards

```bash
kubectl port-forward -n eth-indexer svc/api-server 8080:80
kubectl port-forward -n eth-indexer svc/grafana 3000:3000
kubectl port-forward -n eth-indexer svc/prometheus 9090:9090
```
