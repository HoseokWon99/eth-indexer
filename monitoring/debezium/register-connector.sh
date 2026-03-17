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

echo "Registering Debezium PostgreSQL connector..."
curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"eth-indexer-connector\",
        \"config\": {
            \"connector.class\": \"io.debezium.connector.postgresql.PostgresConnector\",
            \"database.hostname\": \"postgres\",
            \"database.port\": \"5432\",
            \"database.user\": \"${POSTGRES_USER:-postgres}\",
            \"database.password\": \"${POSTGRES_PASSWORD:-postgres}\",
            \"database.dbname\": \"${POSTGRES_DB:-eth_indexer}\",
            \"topic.prefix\": \"eth-indexer\",
            \"table.include.list\": \"public.event_records\",
            \"plugin.name\": \"pgoutput\",
            \"publication.name\": \"dbz_publication\",
            \"publication.autocreate.mode\": \"filtered\",
            \"snapshot.mode\": \"initial\",
            \"transforms\": \"unwrap\",
            \"transforms.unwrap.type\": \"io.debezium.transforms.ExtractNewRecordState\",
            \"transforms.unwrap.drop.tombstones\": \"true\",
            \"transforms.unwrap.delete.handling.mode\": \"drop\",
            \"key.converter\": \"org.apache.kafka.connect.json.JsonConverter\",
            \"value.converter\": \"org.apache.kafka.connect.json.JsonConverter\",
            \"key.converter.schemas.enable\": \"false\",
            \"value.converter.schemas.enable\": \"false\"
        }
    }" \
    http://kafka-connect:8083/connectors

echo "Connector registered successfully."
