package core

import (
	"context"

	"eth-indexer.dev/libs/common"
)

type State map[string]uint64

type StateStorage interface {
	GetLastBlockNumber(eventName string) (uint64, error)
	SetLastBlockNumber(eventName string, blockNumber uint64) error
	Get() (State, error)
	Save() error
}

type EventRecordsStorage interface {
	SaveAll(ctx context.Context, topic string, records []common.EventRecord) error
}
