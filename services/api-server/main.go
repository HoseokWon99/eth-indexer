package main

import (
	"context"
	"log"

	libsconfig "eth-indexer.dev/libs/config"
	"eth-indexer.dev/services/api-server/api"
	"eth-indexer.dev/services/api-server/config"
	"eth-indexer.dev/services/api-server/core"
	"eth-indexer.dev/services/api-server/storage"
)

func main() {
	options, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("Configuration error: %v", err)
	}

	var eventRecordsStorage core.EventRecordsStorage
	switch options.StorageType {
	case "mongo":
		mongoClient, err := libsconfig.CreateMongoClient(options.Mongo)
		if err != nil {
			log.Fatalf("Failed to create MongoDB client: %v", err)
		}
		col := mongoClient.Database(options.Mongo.Database).Collection("event_records")
		eventRecordsStorage = storage.NewMongoEventRecordsStorage(col)
		log.Println("Using MongoDB storage")
	default:
		pgPool, err := libsconfig.CreatePgConnPool(options.Postgres)
		if err != nil {
			log.Fatalf("Failed to create Postgres connection pool: %v", err)
		}
		eventRecordsStorage = storage.NewPostgresEventRecordsStorage(pgPool)
		log.Println("Using PostgreSQL storage")
	}

	rc, err := config.CreateRedisClient(options.Redis)
	if err != nil {
		log.Fatalf("Failed to create Redis client: %v", err)
	}
	cacheStorage := storage.NewRedisCacheStorage(rc, options.API.TTL)

	handler := api.NewHandler(eventRecordsStorage, cacheStorage, options.Topics)
	apiServer := api.NewServer(handler, int(options.API.Port))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	log.Printf("Starting api-server...")
	if err := apiServer.Start(ctx); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
