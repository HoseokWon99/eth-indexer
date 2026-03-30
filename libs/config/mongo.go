package config

import (
	"os"

	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

type MongoOptions struct {
	URI      string
	Database string
	User     string
	Password string
}

func LoadMongoFromEnv() *MongoOptions {
	return &MongoOptions{
		URI:      GetEnv("MONGO_URI", "mongodb://localhost:27017"),
		Database: GetEnv("MONGO_DB", "eth_indexer"),
		User:     os.Getenv("MONGO_USER"),
		Password: os.Getenv("MONGO_PASSWORD"),
	}
}

func CreateMongoClient(opts *MongoOptions) (*mongo.Client, error) {
	clientOpts := options.Client().ApplyURI(opts.URI)
	if opts.User != "" {
		clientOpts.SetAuth(options.Credential{
			Username: opts.User,
			Password: opts.Password,
		})
	}
	return mongo.Connect(clientOpts)
}
