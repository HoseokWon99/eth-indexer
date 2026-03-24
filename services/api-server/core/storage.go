package core

import (
	"context"

	"eth-indexer.dev/libs/common"
	"eth-indexer.dev/services/api-server/types"
)

type EventRecordsStorage interface {
	FindAll(
		ctx context.Context,
		topic string,
		filters *types.EventRecordFilters,
		paging *common.PagingOptions[types.EventRecordCursor],
	) ([]common.EventRecord, error)
}

type CacheStorage interface {
	Get(ctx context.Context, key string) (types.SearchResponse, bool, error)
	Set(ctx context.Context, key string, value types.SearchResponse) error
}
