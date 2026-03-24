package types

import (
	"time"

	"eth-indexer.dev/libs/common"
)

type EventRecordFilters struct {
	ContractAddress []string                           `json:"contract_address" validate:"omitempty,dive,eth_addr"`
	TxHash          []string                           `json:"tx_hash" validate:"omitempty,dive,eth_hash"`
	BlockHash       []string                           `json:"block_hash" validate:"omitempty,dive,eth_hash"`
	BlockNumber     common.ComparisonFilter[uint64]    `json:"block_number" validate:"omitempty"`
	LogIndex        []uint64                           `json:"log_index" validate:"omitempty,dive,gte=0"`
	Data            map[string]interface{}             `json:"data" validate:"omitempty"`
	Timestamp       common.ComparisonFilter[time.Time] `json:"timestamp" validate:"omitempty"`
}

type EventRecordCursor struct {
	BlockNumber uint64 `json:"block_number"`
	LogIndex    uint64 `json:"log_index"`
}

type SearchResponse struct {
	Count  int                  `json:"count"`
	Result []common.EventRecord `json:"result"`
}
