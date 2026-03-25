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
	eth                 *ethclient.Client
	channel             chan *types.Header
	scanners            []Scanner
	eventRecordsStorage EventRecordsStorage
	stateStorage        StateStorage
	confirmedAfter      uint64
	sub                 ethereum.Subscription
	mu                  sync.RWMutex
}

func NewIndexer(
	eth *ethclient.Client,
	scanners []Scanner,
	eventRecordsStorage EventRecordsStorage,
	stateStorage StateStorage,
	confirmedAfter uint64,
) *Indexer {
	return &Indexer{
		eth:                 eth,
		channel:             make(chan *types.Header),
		scanners:            scanners,
		eventRecordsStorage: eventRecordsStorage,
		stateStorage:        stateStorage,
		confirmedAfter:      confirmedAfter,
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
	for _, sc := range ix.scanners {
		wg.Add(1)
		go func(sc Scanner) {
			log.Printf("[Indexer:%s] Start indexing", sc.EventName())
			defer wg.Done()

			lastBlockNumber, err := ix.stateStorage.GetLastBlockNumber(sc.EventName())
			if err != nil {
				log.Printf("[Indexer:%s] Failed to get last block number %v", sc.EventName(), err)
				return
			}
			fromBlockNumber := lastBlockNumber + 1
			toBlockNumber := blockNumber - ix.confirmedAfter

			records, err := sc.Scan(ctx, fromBlockNumber, toBlockNumber)
			if err != nil {
				log.Printf("[Indexer:%s] Failed to scan blocks %v", sc.EventName(), err)
				return
			}
			if len(records) == 0 {
				log.Printf("[Indexer:%s] No new blocks to scan in range %d-%d", sc.EventName(), fromBlockNumber, toBlockNumber)
				return
			}

			err = ix.eventRecordsStorage.SaveAll(ctx, sc.EventName(), records)
			if err != nil {
				log.Printf("[Indexer:%s] Failed to save records : %v", sc.EventName(), err)
				return
			}

			lastBlockNumber = records[len(records)-1].BlockNumber
			err = ix.stateStorage.SetLastBlockNumber(sc.EventName(), lastBlockNumber)
			if err != nil {
				log.Printf("[Indexer:%s] Failed to save last block number: %v", sc.EventName(), err)
				return
			}
			log.Printf("[Indexer:%s] Successfully indexed blocks in range %d-%d", sc.EventName(), fromBlockNumber, lastBlockNumber)
		}(sc)
	}
	wg.Wait()
}
