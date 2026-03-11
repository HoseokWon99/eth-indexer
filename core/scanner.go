package core

import (
	"context"

	"github.com/ethereum/go-ethereum/common"
)

type Scanner interface {
	Topic0() common.Hash
	EventName() string
	Scan(ctx context.Context, fromBlockNumber, toBlockNumber uint64) ([]EventRecord, error)
}
