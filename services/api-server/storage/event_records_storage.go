package storage

import (
	"context"
	"encoding/json"
	"log"

	"eth-indexer.dev/libs/common"
	"eth-indexer.dev/services/api-server/types"

	sq "github.com/Masterminds/squirrel"
	"github.com/jackc/pgx"
)

type PostgresEventRecordsStorage struct {
	pool *pgx.ConnPool
}

func NewPostgresEventRecordsStorage(pool *pgx.ConnPool) *PostgresEventRecordsStorage {
	return &PostgresEventRecordsStorage{pool: pool}
}

func (ers *PostgresEventRecordsStorage) FindAll(
	ctx context.Context,
	topic string,
	filters *types.EventRecordFilters,
	paging *common.PagingOptions[types.EventRecordCursor],
) ([]common.EventRecord, error) {
	qb := sq.Select("*").From("event_records").
		Where(makePredicate(topic, filters, paging.Cursor)).
		OrderBy("block_number ASC", "log_index ASC")
	if paging.Limit != 0 {
		qb = qb.Limit(paging.Limit)
	}
	sql, args, err := qb.PlaceholderFormat(sq.Dollar).ToSql()
	log.Printf("[Debug] SQL: %s, Args: [ %v]", sql, args)

	if err != nil {
		return nil, err
	}
	rows, err := ers.pool.QueryEx(ctx, sql, nil, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	records := make([]common.EventRecord, 0)
	var (
		tmp     string
		rawData []byte
	)
	for rows.Next() {
		record := common.EventRecord{Data: make(map[string]interface{})}
		err := rows.Scan(
			&tmp,
			&record.ContractAddress,
			&record.TxHash,
			&record.BlockHash,
			&record.BlockNumber,
			&record.LogIndex,
			&rawData,
			&record.Timestamp,
		)
		if err != nil {
			return nil, err
		}
		if len(rawData) > 0 {
			if err := json.Unmarshal(rawData, &record.Data); err != nil {
				return nil, err
			}
		}
		records = append(records, record)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return records, nil
}

func makePredicate(
	topic string,
	filters *types.EventRecordFilters,
	cursor *types.EventRecordCursor,
) sq.Sqlizer {
	preds := []sq.Sqlizer{sq.Eq{"topic": topic}}
	if filters != nil {
		preds = appendEq(preds, "contract_address", filters.ContractAddress)
		preds = appendEq(preds, "tx_hash", filters.TxHash)
		preds = appendEq(preds, "block_hash", filters.BlockHash)
		preds = appendCmp(preds, "block_number", filters.BlockNumber)
		preds = appendEq(preds, "log_index", filters.LogIndex)
		preds = appendGin(preds, "data", filters.Data)
		preds = appendCmp(preds, "timestamp", filters.Timestamp)
	}
	if cursor != nil {
		preds = appendCmp(preds, "block_number", common.ComparisonFilter[uint64]{common.GTE: cursor.BlockNumber})
		preds = appendCmp(preds, "log_index", common.ComparisonFilter[uint64]{common.GTE: cursor.LogIndex})
	}
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

func appendCmp[T any](preds []sq.Sqlizer, column string, filter common.ComparisonFilter[T]) []sq.Sqlizer {
	for op, v := range filter {
		switch op {
		case common.LT:
			preds = append(preds, sq.Lt{column: v})
		case common.LTE:
			preds = append(preds, sq.LtOrEq{column: v})
		case common.GT:
			preds = append(preds, sq.Gt{column: v})
		case common.GTE:
			preds = append(preds, sq.GtOrEq{column: v})
		case common.EQ:
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
