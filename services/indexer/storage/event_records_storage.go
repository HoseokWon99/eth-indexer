package storage

import (
	"context"
	"encoding/json"
	"errors"

	"eth-indexer.dev/libs/common"

	"github.com/jackc/pgx"
	"github.com/jackc/pgx/pgtype"
)

const insertSQL = `INSERT INTO event_records (topic, contract_address, tx_hash, block_hash, block_number, log_index, data, timestamp) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) ON CONFLICT (tx_hash, log_index) DO NOTHING`

var columnTypes = []pgtype.OID{
	pgtype.TextOID,        // topic
	pgtype.VarcharOID,     // contract_address
	pgtype.VarcharOID,     // tx_hash
	pgtype.VarcharOID,     // block_hash
	pgtype.NumericOID,     // block_number
	pgtype.NumericOID,     // log_index
	pgtype.JSONBOID,       // data
	pgtype.TimestamptzOID, // timestamp
}

type PostgresEventRecordsStorage struct {
	pool *pgx.ConnPool
}

func NewPostgresEventRecordsStorage(pool *pgx.ConnPool) *PostgresEventRecordsStorage {
	return &PostgresEventRecordsStorage{pool: pool}
}

func (ers *PostgresEventRecordsStorage) SaveAll(ctx context.Context, topic string, records []common.EventRecord) error {
	batch := ers.pool.BeginBatch()
	params := make([]interface{}, 8)
	params[0] = topic
	for _, record := range records {
		params[1] = record.ContractAddress
		params[2] = record.TxHash
		params[3] = record.BlockHash
		params[4] = record.BlockNumber
		params[5] = record.LogIndex
		params[6], _ = json.Marshal(record.Data)
		params[7] = record.Timestamp
		batch.Queue(insertSQL, params, columnTypes, nil)
	}
	err1 := batch.Send(ctx, nil)
	err2 := batch.Close()
	return errors.Join(err1, err2)
}
