package core

import (
	"context"
	"fmt"
	"log"
	"sync"
)

type Worker struct {
	name                string
	scanners            []Scanner
	eventRecordsStorage EventRecordsStorage
	stateStorage        StateStorage
}

func NewWorker(name string, scanners []Scanner, ers EventRecordsStorage, ss StateStorage) *Worker {
	return &Worker{
		name:                name,
		scanners:            scanners,
		eventRecordsStorage: ers,
		stateStorage:        ss,
	}
}

func (w *Worker) Name() string {
	return w.name
}

// IndexBlocks runs all scanners in parallel for one block.
// State keys are "workerName:eventName" to avoid cross-worker collisions.
func (w *Worker) IndexBlocks(ctx context.Context, blockNumber, confirmedAfter uint64) {
	var wg sync.WaitGroup
	for _, sc := range w.scanners {
		wg.Add(1)
		go func(sc Scanner) {
			defer wg.Done()
			stateKey := fmt.Sprintf("%s:%s", w.name, sc.EventName())
			log.Printf("[Worker:%s/%s] Start indexing", w.name, sc.EventName())

			lastBlockNumber, err := w.stateStorage.GetLastBlockNumber(stateKey)
			if err != nil {
				log.Printf("[Worker:%s/%s] Failed to get last block number: %v", w.name, sc.EventName(), err)
				return
			}
			if blockNumber <= confirmedAfter {
				return
			}
			fromBlockNumber := lastBlockNumber + 1
			toBlockNumber := blockNumber - confirmedAfter

			records, err := sc.Scan(ctx, fromBlockNumber, toBlockNumber)
			if err != nil {
				log.Printf("[Worker:%s/%s] Failed to scan blocks: %v", w.name, sc.EventName(), err)
				return
			}
			if len(records) == 0 {
				log.Printf("[Worker:%s/%s] No new blocks to scan in range %d-%d", w.name, sc.EventName(), fromBlockNumber, toBlockNumber)
				return
			}

			if err = w.eventRecordsStorage.SaveAll(ctx, sc.EventName(), records); err != nil {
				log.Printf("[Worker:%s/%s] Failed to save records: %v", w.name, sc.EventName(), err)
				return
			}

			lastBlockNumber = records[len(records)-1].BlockNumber
			if err = w.stateStorage.SetLastBlockNumber(stateKey, lastBlockNumber); err != nil {
				log.Printf("[Worker:%s/%s] Failed to save last block number: %v", w.name, sc.EventName(), err)
				return
			}
			log.Printf("[Worker:%s/%s] Successfully indexed blocks in range %d-%d", w.name, sc.EventName(), fromBlockNumber, lastBlockNumber)
		}(sc)
	}
	wg.Wait()
}
