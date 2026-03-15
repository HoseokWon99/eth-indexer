package core

import (
	"cmp"
	"context"
	"log"
	"slices"
)

type Worker struct {
	scanner             Scanner
	eventRecordsStorage EventRecordsStorage
	confirmedAfter      uint64
	lastBlockNumber     uint64
}

func NewWorker(
	scanner Scanner,
	eventRecordsStorage EventRecordsStorage,
	confirmedAfter uint64,
	offsetBlockNumber uint64,
) *Worker {
	return &Worker{
		scanner:             scanner,
		eventRecordsStorage: eventRecordsStorage,
		confirmedAfter:      confirmedAfter,
		lastBlockNumber:     offsetBlockNumber,
	}
}

func (w *Worker) EventName() string {
	return w.scanner.EventName()
}

func (w *Worker) LastBlockNumber() uint64 {
	return w.lastBlockNumber
}

func (w *Worker) IndexBlocks(ctx context.Context, blockNumber uint64) error {
	records, err := w.scanBlocks(ctx, blockNumber)
	if err != nil {
		return err
	}
	if len(records) == 0 {
		log.Printf("[Worker:%s] Nothing to be indexed", w.EventName())
		return nil
	}
	slices.SortFunc(records, func(a, b EventRecord) int {
		return cmp.Compare(a.BlockNumber, b.BlockNumber)
	})
	if err = w.eventRecordsStorage.SaveAll(ctx, w.EventName(), records); err == nil {
		lower := records[0].BlockNumber
		upper := records[len(records)-1].BlockNumber
		log.Printf("[Worker:%s] Successfully indexed blocks from %d to %d", w.EventName(), lower, upper)
		w.lastBlockNumber = upper
	}
	return err
}

func (w *Worker) scanBlocks(ctx context.Context, blockNumber uint64) ([]EventRecord, error) {
	fromBlockNumber := w.lastBlockNumber + 1
	toBlockNumber := blockNumber - w.confirmedAfter
	if fromBlockNumber > toBlockNumber {
		return make([]EventRecord, 0), nil
	}
	return w.scanner.Scan(ctx, fromBlockNumber, toBlockNumber)
}
