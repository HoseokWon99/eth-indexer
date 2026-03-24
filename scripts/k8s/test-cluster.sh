#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="eth-indexer"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KAFKA_COMPOSE="$ROOT/test/kafka/docker-compose.kafka.yml"
ANVIL_COMPOSE="$ROOT/test/anvil/docker-compose.anvil.yml"

# ── helpers ────────────────────────────────────────────────────────────────────
info()  { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ── 1. cluster down ────────────────────────────────────────────────────────────
if minikube status -p "$CLUSTER_NAME" &>/dev/null; then
  info "Tearing down existing cluster '$CLUSTER_NAME'..."
  minikube delete -p "$CLUSTER_NAME"
else
  info "No existing cluster found, skipping cluster down."
fi

# ── 2. kafka & anvil down ──────────────────────────────────────────────────────
info "Stopping Kafka..."
docker compose -f "$KAFKA_COMPOSE" down --remove-orphans 2>/dev/null || true

info "Stopping Anvil..."
docker compose -f "$ANVIL_COMPOSE" down --remove-orphans 2>/dev/null || true

# ── 3. load local credentials from .env ───────────────────────────────────────
ENV_FILE="$ROOT/.env"
if [[ -f "$ENV_FILE" ]]; then
  info "Sourcing $ENV_FILE for local credentials..."
  set -a; source "$ENV_FILE"; set +a
fi
export ETH_INDEXER_ENV_LOADED=1

# Use local postgres credentials
LOCAL_PG_USER="${POSTGRES_USER:-test}"
LOCAL_PG_PASSWORD="${POSTGRES_PASSWORD:-0000}"
LOCAL_PG_HOST="${POSTGRES_HOST:-localhost}"
LOCAL_PG_DB="${POSTGRES_DB:-eth_indexer}"

info "Using local Postgres: user=$LOCAL_PG_USER db=$LOCAL_PG_DB"

# ── 4. kafka & anvil up ────────────────────────────────────────────────────────
info "Starting Kafka..."
docker compose -f "$KAFKA_COMPOSE" up -d

info "Waiting for Kafka to be healthy..."
for i in $(seq 1 30); do
  status=$(docker inspect --format '{{.State.Health.Status}}' eth-indexer-kafka-test 2>/dev/null || echo "unknown")
  [[ "$status" == "healthy" ]] && break
  [[ $i -eq 30 ]] && error "Kafka did not become healthy in time"
  echo "  ($i/30) status=$status, retrying in 5s..."
  sleep 5
done

info "Starting Anvil..."
docker compose -f "$ANVIL_COMPOSE" up -d anvil

info "Waiting for Anvil to be healthy..."
for i in $(seq 1 15); do
  status=$(docker inspect --format '{{.State.Health.Status}}' eth-indexer-anvil 2>/dev/null || echo "unknown")
  [[ "$status" == "healthy" ]] && break
  [[ $i -eq 15 ]] && error "Anvil did not become healthy in time"
  echo "  ($i/15) status=$status, retrying in 2s..."
  sleep 2
done

# ── 5. contract deployment ────────────────────────────────────────────────────
info "Waiting for Anvil RPC..."
"$ROOT/scripts/anvil/wait-for-rpc.sh" "http://localhost:8545"

info "Deploying contracts..."
RPC_URL="http://localhost:8545" "$ROOT/scripts/anvil/deploy-contracts.sh"

# Read deployed addresses and export as env var for the indexer configmap
DEPLOYED="$ROOT/deployed-addresses.json"
if [[ -f "$DEPLOYED" ]]; then
  TOKEN1=$(jq -r '.token1' "$DEPLOYED")
  TOKEN2=$(jq -r '.token2' "$DEPLOYED")
  info "Deployed contract addresses: $TOKEN1, $TOKEN2"
  export INDEXER_CONTRACT_ADDRESSES="$TOKEN1,$TOKEN2"
else
  error "deployed-addresses.json not found; contract deployment may have failed"
fi

# ── 6. cluster up ──────────────────────────────────────────────────────────────
info "Starting cluster..."

export POSTGRES_USER="$LOCAL_PG_USER"
export POSTGRES_PASSWORD="$LOCAL_PG_PASSWORD"
export POSTGRES_DB="$LOCAL_PG_DB"
export POSTGRES_HOST="host.minikube.internal"
export REDIS_HOST="host.minikube.internal"
export REDIS_PASSWORD="${REDIS_PASSWORD:-}"
export KAFKA_HOST="host.minikube.internal"
export RPC_HOST="host.minikube.internal"
export ETHEREUM_RPC_URL="ws://host.minikube.internal:8545"
export GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
export GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"
export GATEWAY_HOST="${GATEWAY_HOST:-localhost}"
# Anvil does not auto-mine; set to 0 so events are indexed immediately
export INDEXER_CONFIRMED_AFTER=0

"$ROOT/scripts/k8s/cluster-up.sh"

