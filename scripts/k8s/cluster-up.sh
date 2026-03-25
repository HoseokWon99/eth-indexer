#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="eth-indexer"
CPUS=4
MEMORY=6144  # MB
DISK=30000   # MB

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ── helpers ────────────────────────────────────────────────────────────────────
info()  { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

require() {
  command -v "$1" &>/dev/null || error "'$1' is not installed."
}

# ── preflight ─────────────────────────────────────────────────────────────────
require minikube
require kubectl
require docker
require envsubst

# ── cluster ───────────────────────────────────────────────────────────────────
if minikube status -p "$CLUSTER_NAME" &>/dev/null; then
  info "Cluster '$CLUSTER_NAME' already running."
else
  info "Starting minikube cluster '$CLUSTER_NAME' (${CPUS} CPUs, ${MEMORY}MB RAM)..."
  minikube start \
    --profile "$CLUSTER_NAME" \
    --cpus "$CPUS" \
    --memory "$MEMORY" \
    --disk-size "$DISK" \
    --driver docker
fi

minikube profile "$CLUSTER_NAME"

# ── Gateway API CRDs ──────────────────────────────────────────────────────────
info "Installing Gateway API CRDs..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

# ── NGINX Gateway Fabric ──────────────────────────────────────────────────────
info "Installing NGINX Gateway Fabric CRDs..."
kubectl apply -f https://raw.githubusercontent.com/nginxinc/nginx-gateway-fabric/v1.5.1/deploy/crds.yaml

info "Installing NGINX Gateway Fabric..."
kubectl apply -f https://raw.githubusercontent.com/nginxinc/nginx-gateway-fabric/v1.5.1/deploy/default/deploy.yaml

info "Waiting for NGINX Gateway Fabric to be ready..."
kubectl wait --timeout=120s --for=condition=Available \
  deployment/nginx-gateway -n nginx-gateway

# ── docker images ─────────────────────────────────────────────────────────────
info "Building Docker images inside minikube's daemon..."
eval "$(minikube docker-env -p "$CLUSTER_NAME")"

docker build -f "$ROOT/services/indexer/Dockerfile"     -t eth-indexer:latest     "$ROOT"
docker build -f "$ROOT/services/api-server/Dockerfile"  -t eth-api-server:latest  "$ROOT"
docker build -f "$ROOT/services/dashboard/Dockerfile" -t eth-dashboard:latest "$ROOT"

# ── secrets ───────────────────────────────────────────────────────────────────
info "Applying secrets..."

ENV_FILE="$ROOT/.env"
# Only source .env when not already loaded by a parent script (e.g. test-cluster.sh).
# Sourcing again would clobber overrides already exported by the caller.
if [[ -z "${ETH_INDEXER_ENV_LOADED:-}" && -f "$ENV_FILE" ]]; then
  info "Sourcing $ENV_FILE"
  set -a; source "$ENV_FILE"; set +a
fi

# Validate required vars
: "${POSTGRES_USER:?POSTGRES_USER is not set}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is not set}"
: "${POSTGRES_DB:?POSTGRES_DB is not set}"
: "${REDIS_PASSWORD?REDIS_PASSWORD is not set}"  # allow empty string
: "${RPC_HOST:?RPC_HOST is not set}"
: "${ETHEREUM_RPC_URL:?ETHEREUM_RPC_URL is not set}"
: "${GRAFANA_ADMIN_USER:?GRAFANA_ADMIN_USER is not set}"
: "${GRAFANA_ADMIN_PASSWORD:?GRAFANA_ADMIN_PASSWORD is not set}"
: "${GATEWAY_HOST:?GATEWAY_HOST is not set}"
: "${POSTGRES_HOST:?POSTGRES_HOST is not set}"
: "${REDIS_HOST:?REDIS_HOST is not set}"
: "${KAFKA_HOST:?KAFKA_HOST is not set}"
: "${INDEXER_CONTRACT_ADDRESSES:?INDEXER_CONTRACT_ADDRESSES is not set}"

# ── manifests ─────────────────────────────────────────────────────────────────
info "Applying namespace..."
kubectl apply -f "$ROOT/k8s/namespace.yaml"

envsubst < "$ROOT/k8s/secrets.yaml" | kubectl apply -f -

info "Applying external service mappings..."
envsubst < "$ROOT/k8s/external-services.yaml" | kubectl apply -f -

info "Applying Kafka Connect + Debezium..."
kubectl apply -f "$ROOT/k8s/kafka-connect/"

info "Applying application services..."
envsubst < "$ROOT/k8s/indexer/configmap.yaml" | kubectl apply -f -
kubectl apply -f "$ROOT/k8s/indexer/deployment.yaml"
kubectl apply -f "$ROOT/k8s/api-server/"
kubectl apply -f "$ROOT/k8s/dashboard/"

info "Applying ingress..."
envsubst < "$ROOT/k8s/gateway.yaml" | kubectl apply -f -

info "Applying monitoring..."
kubectl apply -f "$ROOT/k8s/monitoring/kafka-exporter/"
kubectl apply -f "$ROOT/k8s/monitoring/prometheus/"
find "$ROOT/k8s/monitoring/grafana" -name "*.yaml" | sort | xargs -I{} sh -c 'envsubst '"'"'${GATEWAY_HOST}'"'"' < "$1" | kubectl apply -f -' _ {}

# ── done ──────────────────────────────────────────────────────────────────────
info "Done. Check pod status:"
echo ""
echo "  kubectl get pods -n eth-indexer"
echo ""
info "Port-forward API server:"
echo ""
echo "  kubectl port-forward -n eth-indexer svc/api-server 8080:80"
echo ""
info "Port-forward Grafana:"
echo ""
echo "  kubectl port-forward -n eth-indexer svc/grafana 3000:3000"
echo ""