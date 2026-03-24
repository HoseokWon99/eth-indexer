package core

import (
	"context"

	"eth-indexer.dev/libs/common"
	ethcommon "github.com/ethereum/go-ethereum/common"
)

type Scanner interface {
	Topic0() ethcommon.Hash
	EventName() string
	Scan(ctx context.Context, fromBlockNumber, toBlockNumber uint64) ([]common.EventRecord, error)
}
