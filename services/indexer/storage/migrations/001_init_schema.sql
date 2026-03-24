-- Initial schema for eth-indexer
-- This script will be automatically executed when the Postgres container starts

-- Create event_records table
CREATE TABLE IF NOT EXISTS event_records (
    topic TEXT NOT NULL,
    contract_address VARCHAR(42) NOT NULL,
    tx_hash VARCHAR(66) NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    block_number BIGINT NOT NULL,
    log_index BIGINT NOT NULL,
    data JSONB NOT NULL DEFAULT '{}',
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Primary key constraint
    PRIMARY KEY (tx_hash, log_index)
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_event_records_topic
    ON event_records (topic);

CREATE INDEX IF NOT EXISTS idx_event_records_contract_address
    ON event_records (contract_address);

CREATE INDEX IF NOT EXISTS idx_event_records_block_number
    ON event_records (block_number DESC);

CREATE INDEX IF NOT EXISTS idx_event_records_block_hash
    ON event_records (block_hash);

CREATE INDEX IF NOT EXISTS idx_event_records_timestamp
    ON event_records (timestamp DESC);

-- GIN index for JSONB data queries
CREATE INDEX IF NOT EXISTS idx_event_records_data
    ON event_records USING GIN (data);

-- Composite index for topic + block_number queries (common query pattern)
CREATE INDEX IF NOT EXISTS idx_event_records_topic_block
    ON event_records (topic, block_number DESC);

-- Composite index for topic + contract_address queries
CREATE INDEX IF NOT EXISTS idx_event_records_topic_contract
    ON event_records (topic, contract_address);

-- Comment on table
COMMENT ON TABLE event_records IS 'Stores indexed Ethereum smart contract event records';

-- Comment on columns
COMMENT ON COLUMN event_records.topic IS 'Event name/topic (e.g., Transfer, Approval)';
COMMENT ON COLUMN event_records.contract_address IS 'Contract address that emitted the event (0x-prefixed)';
COMMENT ON COLUMN event_records.tx_hash IS 'Transaction hash (0x-prefixed)';
COMMENT ON COLUMN event_records.block_hash IS 'Block hash (0x-prefixed)';
COMMENT ON COLUMN event_records.block_number IS 'Block number where the event was emitted';
COMMENT ON COLUMN event_records.log_index IS 'Log index within the transaction';
COMMENT ON COLUMN event_records.data IS 'Decoded event data as JSONB';
COMMENT ON COLUMN event_records.timestamp IS 'Timestamp when the event was indexed';
