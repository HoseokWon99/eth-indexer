package service

import (
	"context"
	"eth-indexer/core"
	"log"
	"sync"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
	"golang.org/x/sync/errgroup"
)

type IndexerService struct {
	eth          *ethclient.Client
	channel      chan *types.Header
	workers      []*core.Worker
	stateStorage core.StateStorage
	sub          ethereum.Subscription
	mu           sync.RWMutex
}

func NewIndexerService(
	eth *ethclient.Client,
	scanners []core.Scanner,
	eventRecordsStorage core.EventRecordsStorage,
	stateStorage core.StateStorage,
	confirmedAfter uint64,
	defaultOffset uint64,
) *IndexerService {
	// load initial state
	state, err := stateStorage.Get()
	if err != nil {
		log.Printf("Failed to load state: %v", err)
		state = make(map[string]uint64)
	}
	// create workers
	workers := make([]*core.Worker, len(scanners))
	channel := make(chan *types.Header)
	for i, scanner := range scanners {
		offset, ok := state[scanner.EventName()]
		if !ok {
			offset = defaultOffset
		}
		workers[i] = core.NewWorker(channel, scanner, eventRecordsStorage, confirmedAfter, offset)
	}
	return &IndexerService{
		eth:          eth,
		workers:      workers,
		stateStorage: stateStorage,
		channel:      channel,
	}
}

func (ix *IndexerService) State() map[string]uint64 {
	ix.mu.RLock()
	defer ix.mu.RUnlock()
	return ix.getState()
}

func (ix *IndexerService) Run(ctx context.Context) (err error) {
	if ix.sub, err = ix.eth.SubscribeNewHead(ctx, ix.channel); err != nil {
		close(ix.channel)
		return err
	}
	eg, runCtx := errgroup.WithContext(ctx)
	for _, w := range ix.workers {
		eg.Go(func() error { return w.Run(runCtx) })
	}
	eg.Go(func() error {
		for {
			select {
			case <-runCtx.Done():
				return runCtx.Err()
			case err := <-ix.sub.Err():
				return err
			}
		}
	})
	err = eg.Wait()
	ix.Close()
	return err
}

func (ix *IndexerService) SaveState() error {
	ix.mu.Lock()
	defer ix.mu.Unlock()
	return ix.stateStorage.Set(ix.getState())
}

func (ix *IndexerService) Close() {
	ix.mu.Lock()
	defer ix.mu.Unlock()
	if ix.sub != nil {
		ix.sub.Unsubscribe()
	}
	close(ix.channel)
	ix.eth.Close()
	if err := ix.stateStorage.Set(ix.getState()); err != nil {
		log.Printf("Failed to save state: %v", err)
	}
}

func (ix *IndexerService) getState() map[string]uint64 {
	state := make(map[string]uint64)
	for _, w := range ix.workers {
		state[w.EventName()] = w.LastBlockNumber()
	}
	return state
}
