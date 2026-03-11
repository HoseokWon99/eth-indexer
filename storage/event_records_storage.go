package storage

import (
	"context"
	"encoding/json"
	"errors"
	"eth-indexer/core"
	"time"

	sq "github.com/Masterminds/squirrel"
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

func (ers *PostgresEventRecordsStorage) SaveAll(ctx context.Context, topic string, records []core.EventRecord) error {
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

func (ers *PostgresEventRecordsStorage) FindAll(ctx context.Context, topic string, filters core.EventRecordFilters) ([]core.EventRecord, error) {
	// Build query
	sql, args, err := sq.Select("*").From("event_records").
		Where(makePredicate(topic, filters)).
		PlaceholderFormat(sq.Dollar).
		ToSql()
	if err != nil {
		return nil, err
	}
	// Execute with pgx
	rows, err := ers.pool.QueryEx(ctx, sql, nil, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	// Parse each row
	records := make([]core.EventRecord, 0)
	var (
		contractAddress string
		txHash          string
		blockHash       string
		blockNumber     uint64
		logIndex        uint64
		rawData         []byte
		timestamp       time.Time
	)
	for rows.Next() {
		err := rows.Scan(
			&topic,
			&contractAddress,
			&txHash,
			&blockHash,
			&blockNumber,
			&logIndex,
			&rawData,
			&timestamp,
		)
		if err != nil {
			return nil, err
		}
		data := make(map[string]interface{})
		if len(rawData) > 0 {
			if err := json.Unmarshal(rawData, &data); err != nil {
				return nil, err
			}
		}
		records = append(records, core.EventRecord{
			ContractAddress: contractAddress,
			TxHash:          txHash,
			BlockHash:       blockHash,
			BlockNumber:     blockNumber,
			LogIndex:        logIndex,
			Data:            data,
			Timestamp:       timestamp,
		})
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return records, nil
}

func makePredicate(topic string, filters core.EventRecordFilters) sq.Sqlizer {
	preds := []sq.Sqlizer{sq.Eq{"topic": topic}}
	preds = appendEq(preds, "contract_address", filters.ContractAddress)
	preds = appendEq(preds, "tx_hash", filters.TxHash)
	preds = appendEq(preds, "block_hash", filters.BlockHash)
	preds = appendCmp(preds, "block_number", filters.BlockNumber)
	preds = appendEq(preds, "log_index", filters.LogIndex)
	preds = appendGin(preds, "data", filters.Data)
	preds = appendCmp(preds, "timestamp", filters.Timestamp)
	if len(preds) == 1 {
		return preds[0]
	}
	return sq.And(preds)
}

func appendEq[T any](preds []sq.Sqlizer, column string, values []T) []sq.Sqlizer {
	if len(values) == 0 {
		return preds
	}
	if len(values) == 1 {
		return append(preds, sq.Eq{column: values[0]})
	}
	return append(preds, sq.Eq{column: values})
}

func appendCmp[T any](preds []sq.Sqlizer, column string, filter core.ComparisonFilter[T]) []sq.Sqlizer {
	for op, v := range filter {
		switch op {
		case core.LT:
			preds = append(preds, sq.Lt{column: v})
		case core.LTE:
			preds = append(preds, sq.LtOrEq{column: v})
		case core.GT:
			preds = append(preds, sq.Gt{column: v})
		case core.GTE:
			preds = append(preds, sq.GtOrEq{column: v})
		case core.EQ:
			preds = append(preds, sq.Eq{column: v})
		}
	}
	return preds
}

func appendGin(preds []sq.Sqlizer, column string, jsonb map[string]interface{}) []sq.Sqlizer {
	if len(jsonb) == 0 {
		return preds
	}
	raw, _ := json.Marshal(jsonb)
	expr := sq.Expr("? @> '?'", column, string(raw))
	return append(preds, expr)
}
