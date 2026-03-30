package main

import (
	"context"
	"errors"
	"fmt"
	"log"

	libsconfig "eth-indexer.dev/libs/config"
	"eth-indexer.dev/services/indexer/api"
	"eth-indexer.dev/services/indexer/config"
	"eth-indexer.dev/services/indexer/core"
	"eth-indexer.dev/services/indexer/scanner"
	"eth-indexer.dev/services/indexer/storage"
	"github.com/ethereum/go-ethereum/ethclient"
	"golang.org/x/sync/errgroup"
)

func main() {
	options, err := config.LoadOptions()
	if err != nil {
		panic(err)
	}

	var eventRecordsStorage core.EventRecordsStorage
	switch options.StorageType {
	case "mongo":
		mongoClient, err := libsconfig.CreateMongoClient(options.Mongo)
		if err != nil {
			panic(err)
		}
		col := mongoClient.Database(options.Mongo.Database).Collection("event_records")
		if err := storage.EnsureIndexes(col); err != nil {
			panic(err)
		}
		eventRecordsStorage = storage.NewMongoEventRecordsStorage(col)
		log.Println("Using MongoDB storage")
	default:
		pgPool, err := libsconfig.CreatePgConnPool(options.Postgres)
		if err != nil {
			panic(err)
		}
		if err := storage.Migrate(pgPool); err != nil {
			panic(err)
		}
		eventRecordsStorage = storage.NewPostgresEventRecordsStorage(pgPool)
		log.Println("Using PostgreSQL storage")
	}

	allStateKeys := []string{}
	for _, wc := range options.Indexer.Workers {
		for _, en := range wc.EventNames {
			allStateKeys = append(allStateKeys, fmt.Sprintf("%s:%s", wc.Name, en))
		}
	}
	stateStorage, err := storage.NewSimpleStateStorage(
		options.Indexer.StatusFilePath,
		allStateKeys,
		options.Indexer.OffsetBlockNumber,
	)
	if err != nil {
		panic(err)
	}

	eth, err := ethclient.Dial(options.Indexer.RpcUrl)
	if err != nil {
		panic(err)
	}

	workers := make([]*core.Worker, 0, len(options.Indexer.Workers))
	for _, wc := range options.Indexer.Workers {
		scanners := make([]core.Scanner, 0, len(wc.EventNames))
		for _, en := range wc.EventNames {
			scn, err := scanner.NewEventRecordsScanner(eth, wc.ABI, en, wc.ContractAddresses)
			if err != nil {
				log.Fatalf("Failed to create scanner for worker %q event %q: %v", wc.Name, en, err)
			}
			scanners = append(scanners, scn)
		}
		workers = append(workers, core.NewWorker(wc.Name, scanners, eventRecordsStorage, stateStorage))
	}

	indexer := core.NewIndexer(
		eth,
		workers,
		stateStorage,
		options.Indexer.ConfirmedAfter,
	)
	defer indexer.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	srv := api.NewServer(indexer, options.API.Port)

	eg, egCtx := errgroup.WithContext(ctx)
	eg.Go(func() error { return srv.Start(egCtx) })
	eg.Go(func() error { return indexer.Run(egCtx) })

	log.Printf("Starting indexer service...")
	if err := eg.Wait(); err != nil && !errors.Is(err, context.Canceled) {
		log.Fatalf("Indexer service error: %v", err)
	}
}
