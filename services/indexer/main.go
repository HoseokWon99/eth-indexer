package main

import (
	"context"
	"errors"
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

	pgPool, err := libsconfig.CreatePgConnPool(options.Postgres)
	if err != nil {
		panic(err)
	}

	if err := storage.Migrate(pgPool); err != nil {
		panic(err)
	}

	eventRecordsStorage := storage.NewPostgresEventRecordsStorage(pgPool)

	stateStorage, err := storage.NewSimpleStateStorage(
		options.Indexer.StatusFilePath,
		options.Indexer.EventNames,
		options.Indexer.OffsetBlockNumber,
	)
	if err != nil {
		panic(err)
	}

	eth, err := ethclient.Dial(options.Indexer.RpcUrl)
	if err != nil {
		panic(err)
	}
	scanners := make([]core.Scanner, 0, len(options.Indexer.EventNames))
	for _, en := range options.Indexer.EventNames {
		scn, err := scanner.NewEventRecordsScanner(
			eth,
			options.Indexer.ABI,
			en,
			options.Indexer.ContractAddresses,
		)
		if err != nil {
			log.Fatalf("Failed to create scanner for event '%s': %v", en, err)
		}
		scanners = append(scanners, scn)
	}

	indexer := core.NewIndexer(
		eth,
		scanners,
		eventRecordsStorage,
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
