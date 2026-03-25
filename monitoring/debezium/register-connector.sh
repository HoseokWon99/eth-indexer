#!/bin/sh
set -e

echo "Waiting for Kafka Connect to be ready..."
until curl -sf http://kafka-connect:8083/ > /dev/null 2>&1; do
    echo "Kafka Connect not ready, sleeping 5s..."
    sleep 5
done

# Idempotent: skip if already registered
if curl -sf http://kafka-connect:8083/connectors/eth-indexer-connector > /dev/null 2>&1; then
    echo "Connector already registered, skipping."
    exit 0
fi

POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-eth_indexer}"

echo "Registering Debezium PostgreSQL connector..."
curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "$(envsubst < "$(dirname "$0")/connector-config.json")" \
    http://kafka-connect:8083/connectors

echo "Connector registered successfully."
