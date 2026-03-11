package main

import (
	"context"
	"errors"
	"eth-indexer/api"
	"eth-indexer/config"
	"eth-indexer/core"
	"eth-indexer/scanner"
	"eth-indexer/service"
	"eth-indexer/storage"
	"log"
	"os"

	"github.com/ethereum/go-ethereum/ethclient"
)

func main() {
	// Load configuration
	options, err := config.Load(os.Getenv("CONFIG_PATH"))
	if err != nil {
		log.Fatalf("Configuration error: %v", err)
	}
	// Create EventRecordsStorage
	pgPool, err := config.CreatePgConnPool(options.Postgres)
	if err != nil {
		log.Fatalf("Failed to create Postgres connection pool: %v", err)
	}
	eventRecordsStorage := storage.NewPostgresEventRecordsStorage(pgPool)
	// Create StateStorage
	stateStorage, err := storage.NewSimpleStateStorage(options.Indexer.StatusFilePath)
	if err != nil {
		log.Fatalf("Failed to create state storage: %v", err)
	}
	// Create CacheStorage
	rc, err := config.CreateRedisClient(options.Redis)
	if err != nil {
		log.Fatalf("Failed to create Redis client: %v", err)
	}
	cacheStorage := storage.NewRedisCacheStorage(rc)
	// Create ethereum client
	eth, err := ethclient.Dial(options.Indexer.RpcUrl)
	if err != nil {
		log.Fatalf("Failed to create ethereum client: %v", err)
	}
	// Create scanners
	scanners := make([]core.Scanner, 0, len(options.Indexer.EventNames))
	for _, en := range options.Indexer.EventNames {
		scn, err := scanner.NewEventRecordsScanner(eth, options.Indexer.ABI, en, options.Indexer.ContractAddresses)
		if err != nil {
			log.Fatalf("Failed to create scanner for event '%s': %v", en, err)
		}
		scanners = append(scanners, scn)
	}
	// Create indexer service
	indexerService := service.NewIndexerService(
		eth,
		scanners,
		eventRecordsStorage,
		stateStorage,
		options.Indexer.ConfirmedAfter,
		options.Indexer.OffsetBlockNumber,
	)
	defer indexerService.Close()
	// Create search service
	searchService := service.NewSearchService(eventRecordsStorage, cacheStorage, options.API.TTL)

	// Create API handler
	handler := api.NewHandler(
		indexerService,
		searchService,
		options.Indexer.EventNames,
	)

	// Create API server
	apiServer := api.NewServer(handler, int(options.API.Port))

	// Setup context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Run indexer service in background
	go func() {
		if err := indexerService.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
			log.Fatalf("Indexer service error: %v", err)
		}
	}()

	// Run API server (blocks until shutdown)
	log.Printf("Starting eth-indexer...")
	if err := apiServer.Start(ctx); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
