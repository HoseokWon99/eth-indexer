package storage

import (
	"context"
	"fmt"
	"sort"

	"eth-indexer.dev/libs/common"
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

// SaveAll bulk-upserts records using $setOnInsert + upsert:true, matching the
// idempotent behaviour of the PostgreSQL ON CONFLICT DO NOTHING approach.
// The topic parameter is ignored because record.Topic already carries the value.
func (s *MongoEventRecordsStorage) SaveAll(ctx context.Context, _ string, records []common.EventRecord) error {
	if len(records) == 0 {
		return nil
	}
	sort.Slice(records, func(i, j int) bool {
		if records[i].BlockNumber != records[j].BlockNumber {
			return records[i].BlockNumber < records[j].BlockNumber
		}
		return records[i].LogIndex < records[j].LogIndex
	})

	models := make([]mongo.WriteModel, 0, len(records))
	for _, r := range records {
		id := fmt.Sprintf("%s:%d", r.TxHash, r.LogIndex)
		doc := bson.D{
			{Key: "_id", Value: id},
			{Key: "topic", Value: r.Topic},
			{Key: "contract_address", Value: r.ContractAddress},
			{Key: "tx_hash", Value: r.TxHash},
			{Key: "block_hash", Value: r.BlockHash},
			{Key: "block_number", Value: r.BlockNumber},
			{Key: "log_index", Value: r.LogIndex},
			{Key: "data", Value: r.Data},
			{Key: "timestamp", Value: r.Timestamp},
		}
		models = append(models, mongo.NewUpdateOneModel().
			SetFilter(bson.D{{Key: "_id", Value: id}}).
			SetUpdate(bson.D{{Key: "$setOnInsert", Value: doc}}).
			SetUpsert(true))
	}

	_, err := s.col.BulkWrite(ctx, models, options.BulkWrite().SetOrdered(false))
	return err
}
