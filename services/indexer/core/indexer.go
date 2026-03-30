package core

import (
	"context"
	"fmt"
	"log"
	"sync"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
	"golang.org/x/sync/errgroup"
)

type Indexer struct {
	eth            *ethclient.Client
	channel        chan *types.Header
	workers        []*Worker
	stateStorage   StateStorage
	confirmedAfter uint64
	sub            ethereum.Subscription
	mu             sync.RWMutex
}

func NewIndexer(
	eth *ethclient.Client,
	workers []*Worker,
	stateStorage StateStorage,
	confirmedAfter uint64,
) *Indexer {
	return &Indexer{
		eth:            eth,
		channel:        make(chan *types.Header),
		workers:        workers,
		stateStorage:   stateStorage,
		confirmedAfter: confirmedAfter,
	}
}

func (ix *Indexer) State() (State, error) {
	ix.mu.RLock()
	defer ix.mu.RUnlock()
	return ix.stateStorage.Get()
}

func (ix *Indexer) Run(ctx context.Context) (err error) {
	if ix.sub, err = ix.eth.SubscribeNewHead(ctx, ix.channel); err != nil {
		close(ix.channel)
		return err
	}
	eg, runCtx := errgroup.WithContext(ctx)
	eg.Go(func() error {
		for {
			select {
			case <-runCtx.Done():
				return runCtx.Err()
			case err := <-ix.sub.Err():
				return err
			case head, ok := <-ix.channel:
				if !ok {
					return fmt.Errorf("channel closed")
				}
				blockNumber := head.Number.Uint64()
				log.Printf("[Indexer] New block: %d", blockNumber)
				ix.indexAll(runCtx, blockNumber)
			}
		}
	})
	err = eg.Wait()
	ix.Close()
	return err
}

func (ix *Indexer) Close() {
	ix.mu.Lock()
	defer ix.mu.Unlock()
	if ix.sub != nil {
		ix.sub.Unsubscribe()
	}
	close(ix.channel)
	ix.eth.Close()
	if err := ix.stateStorage.Save(); err != nil {
		log.Printf("Failed to save state: %v", err)
	}
}

func (ix *Indexer) indexAll(ctx context.Context, blockNumber uint64) {
	var wg sync.WaitGroup
	for _, w := range ix.workers {
		wg.Add(1)
		go func(w *Worker) {
			defer wg.Done()
			w.IndexBlocks(ctx, blockNumber, ix.confirmedAfter)
		}(w)
	}
	wg.Wait()
}
