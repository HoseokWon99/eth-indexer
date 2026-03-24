#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="eth-indexer"

echo "[INFO] Deleting minikube cluster '$CLUSTER_NAME'..."
minikube delete -p "$CLUSTER_NAME"
echo "[INFO] Cluster deleted."
