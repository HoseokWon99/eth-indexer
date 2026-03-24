package main

import (
	"context"
	"log"

	libsconfig "eth-indexer.dev/libs/config"
	"eth-indexer.dev/services/api-server/api"
	"eth-indexer.dev/services/api-server/config"
	"eth-indexer.dev/services/api-server/storage"
)

func main() {
	options, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("Configuration error: %v", err)
	}

	pgPool, err := libsconfig.CreatePgConnPool(options.Postgres)
	if err != nil {
		log.Fatalf("Failed to create Postgres connection pool: %v", err)
	}
	eventRecordsStorage := storage.NewPostgresEventRecordsStorage(pgPool)

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
