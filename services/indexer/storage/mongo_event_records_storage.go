package storage

import (
	"context"
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

// SaveAll groups records by topic and appends them as children to a per-topic
// parent document: { _id: topic, topic, signature, children: [...] }.
// The parent document is created on first insert via $setOnInsert; subsequent
// calls push new children without touching the parent fields.
func (s *MongoEventRecordsStorage) SaveAll(ctx context.Context, records []common.EventRecord) error {
	if len(records) == 0 {
		return nil
	}

	// Group and sort records by topic.
	type group struct {
		signature string
		records   []common.EventRecord
	}
	groups := make(map[string]*group)
	for _, r := range records {
		g, ok := groups[r.Topic]
		if !ok {
			g = &group{signature: r.Signature}
			groups[r.Topic] = g
		}
		g.records = append(g.records, r)
	}
	for _, g := range groups {
		sort.Slice(g.records, func(i, j int) bool {
			if g.records[i].BlockNumber != g.records[j].BlockNumber {
				return g.records[i].BlockNumber < g.records[j].BlockNumber
			}
			return g.records[i].LogIndex < g.records[j].LogIndex
		})
	}

	models := make([]mongo.WriteModel, 0, len(groups))
	for topic, g := range groups {
		children := make(bson.A, 0, len(g.records))
		for _, r := range g.records {
			children = append(children, bson.D{
				{Key: "contract_address", Value: r.ContractAddress},
				{Key: "tx_hash", Value: r.TxHash},
				{Key: "block_hash", Value: r.BlockHash},
				{Key: "block_number", Value: r.BlockNumber},
				{Key: "log_index", Value: r.LogIndex},
				{Key: "data", Value: r.Data},
				{Key: "timestamp", Value: r.Timestamp},
			})
		}
		models = append(models, mongo.NewUpdateOneModel().
			SetFilter(bson.D{{Key: "_id", Value: topic}}).
			SetUpdate(bson.D{
				{Key: "$setOnInsert", Value: bson.D{
					{Key: "topic", Value: topic},
					{Key: "signature", Value: g.signature},
				}},
				{Key: "$push", Value: bson.D{
					{Key: "children", Value: bson.D{
						{Key: "$each", Value: children},
					}},
				}},
			}).
			SetUpsert(true))
	}

	_, err := s.col.BulkWrite(ctx, models, options.BulkWrite().SetOrdered(false))
	return err
}
