package storage

import (
	"context"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// EnsureIndexes creates all required indexes on the event_records collection.
// It is safe to call on every startup (createIndexes is idempotent).
func EnsureIndexes(col *mongo.Collection) error {
	ctx := context.Background()
	_, err := col.Indexes().CreateMany(ctx, []mongo.IndexModel{
		{
			Keys:    bson.D{{Key: "tx_hash", Value: 1}, {Key: "log_index", Value: 1}},
			Options: options.Index().SetUnique(true),
		},
		{Keys: bson.D{{Key: "topic", Value: 1}}},
		{Keys: bson.D{{Key: "contract_address", Value: 1}}},
		{Keys: bson.D{{Key: "block_number", Value: -1}}},
		{Keys: bson.D{{Key: "block_hash", Value: 1}}},
		{Keys: bson.D{{Key: "timestamp", Value: -1}}},
		{Keys: bson.D{{Key: "topic", Value: 1}, {Key: "block_number", Value: -1}}},
		{Keys: bson.D{{Key: "topic", Value: 1}, {Key: "contract_address", Value: 1}}},
	})
	return err
}
