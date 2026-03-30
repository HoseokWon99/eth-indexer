package storage

import (
	"context"
	"fmt"
	"time"

	"eth-indexer.dev/libs/common"
	"eth-indexer.dev/services/api-server/types"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

type MongoEventRecordsStorage struct {
	col *mongo.Collection
}

func NewMongoEventRecordsStorage(col *mongo.Collection) *MongoEventRecordsStorage {
	return &MongoEventRecordsStorage{col: col}
}

func (s *MongoEventRecordsStorage) FindAll(
	ctx context.Context,
	topic string,
	filters *types.EventRecordFilters,
	paging *common.PagingOptions[types.EventRecordCursor],
) ([]common.EventRecord, error) {
	filter := buildMongoFilter(topic, filters, paging.Cursor)
	findOpts := options.Find().SetSort(bson.D{{Key: "block_number", Value: 1}, {Key: "log_index", Value: 1}})
	if paging.Limit != 0 {
		findOpts.SetLimit(int64(paging.Limit))
	}

	cursor, err := s.col.Find(ctx, filter, findOpts)
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	type mongoDoc struct {
		Topic           string                 `bson:"topic"`
		ContractAddress string                 `bson:"contract_address"`
		TxHash          string                 `bson:"tx_hash"`
		BlockHash       string                 `bson:"block_hash"`
		BlockNumber     uint64                 `bson:"block_number"`
		LogIndex        uint64                 `bson:"log_index"`
		Data            map[string]interface{} `bson:"data"`
		Timestamp       time.Time              `bson:"timestamp"`
	}

	records := make([]common.EventRecord, 0)
	for cursor.Next(ctx) {
		var doc mongoDoc
		if err := cursor.Decode(&doc); err != nil {
			return nil, fmt.Errorf("decode error: %w", err)
		}
		records = append(records, common.EventRecord{
			Topic:           doc.Topic,
			ContractAddress: doc.ContractAddress,
			TxHash:          doc.TxHash,
			BlockHash:       doc.BlockHash,
			BlockNumber:     doc.BlockNumber,
			LogIndex:        doc.LogIndex,
			Data:            doc.Data,
			Timestamp:       doc.Timestamp,
		})
	}
	if err := cursor.Err(); err != nil {
		return nil, err
	}
	return records, nil
}

func buildMongoFilter(
	topic string,
	filters *types.EventRecordFilters,
	cursor *types.EventRecordCursor,
) bson.D {
	filter := bson.D{{Key: "topic", Value: topic}}

	if filters != nil {
		if len(filters.ContractAddress) == 1 {
			filter = append(filter, bson.E{Key: "contract_address", Value: filters.ContractAddress[0]})
		} else if len(filters.ContractAddress) > 1 {
			filter = append(filter, bson.E{Key: "contract_address", Value: bson.D{{Key: "$in", Value: filters.ContractAddress}}})
		}

		if len(filters.TxHash) == 1 {
			filter = append(filter, bson.E{Key: "tx_hash", Value: filters.TxHash[0]})
		} else if len(filters.TxHash) > 1 {
			filter = append(filter, bson.E{Key: "tx_hash", Value: bson.D{{Key: "$in", Value: filters.TxHash}}})
		}

		if len(filters.BlockHash) == 1 {
			filter = append(filter, bson.E{Key: "block_hash", Value: filters.BlockHash[0]})
		} else if len(filters.BlockHash) > 1 {
			filter = append(filter, bson.E{Key: "block_hash", Value: bson.D{{Key: "$in", Value: filters.BlockHash}}})
		}

		if len(filters.LogIndex) == 1 {
			filter = append(filter, bson.E{Key: "log_index", Value: filters.LogIndex[0]})
		} else if len(filters.LogIndex) > 1 {
			filter = append(filter, bson.E{Key: "log_index", Value: bson.D{{Key: "$in", Value: filters.LogIndex}}})
		}

		if len(filters.BlockNumber) > 0 {
			filter = append(filter, bson.E{Key: "block_number", Value: buildComparisonFilter(filters.BlockNumber)})
		}

		if len(filters.Timestamp) > 0 {
			filter = append(filter, bson.E{Key: "timestamp", Value: buildComparisonFilter(filters.Timestamp)})
		}

		for k, v := range filters.Data {
			filter = append(filter, bson.E{Key: "data." + k, Value: v})
		}
	}

	if cursor != nil {
		filter = append(filter, bson.E{Key: "block_number", Value: bson.D{{Key: "$gte", Value: cursor.BlockNumber}}})
		filter = append(filter, bson.E{Key: "log_index", Value: bson.D{{Key: "$gte", Value: cursor.LogIndex}}})
	}

	return filter
}

func buildComparisonFilter[T any](f common.ComparisonFilter[T]) bson.D {
	d := bson.D{}
	for op, v := range f {
		switch op {
		case common.LT:
			d = append(d, bson.E{Key: "$lt", Value: v})
		case common.LTE:
			d = append(d, bson.E{Key: "$lte", Value: v})
		case common.GT:
			d = append(d, bson.E{Key: "$gt", Value: v})
		case common.GTE:
			d = append(d, bson.E{Key: "$gte", Value: v})
		case common.EQ:
			d = append(d, bson.E{Key: "$eq", Value: v})
		}
	}
	return d
}
