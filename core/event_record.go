package core

import (
	"context"
	"time"
)

type EventRecord struct {
	ContractAddress string                 `json:"contract_address"`
	TxHash          string                 `json:"tx_hash"`
	BlockHash       string                 `json:"block_hash"`
	BlockNumber     uint64                 `json:"block_number"`
	LogIndex        uint64                 `json:"log_index"`
	Data            map[string]interface{} `json:"data"`
	Timestamp       time.Time              `json:"timestamp"`
}

type ComparisonOp string

const (
	LT  ComparisonOp = "lt"
	LTE ComparisonOp = "lte"
	GT  ComparisonOp = "gt"
	GTE ComparisonOp = "gte"
	EQ  ComparisonOp = "eq"
)

type ComparisonFilter[T any] map[ComparisonOp]T

type EventRecordFilters struct {
	ContractAddress []string                    `json:"contract_address" validate:"omitempty,dive,eth_addr"`
	TxHash          []string                    `json:"tx_hash" validate:"omitempty,dive,eth_hash"`
	BlockHash       []string                    `json:"block_hash" validate:"omitempty,dive,eth_hash"`
	BlockNumber     ComparisonFilter[uint64]    `json:"block_number" validate:"omitempty"`
	LogIndex        []uint64                    `json:"log_index" validate:"omitempty,dive,gte=0"`
	Data            map[string]interface{}      `json:"data" validate:"omitempty"`
	Timestamp       ComparisonFilter[time.Time] `json:"timestamp" validate:"omitempty"`
}

type EventRecordsStorage interface {
	SaveAll(ctx context.Context, topic string, records []EventRecord) error
	FindAll(ctx context.Context, topic string, filters EventRecordFilters) ([]EventRecord, error)
}
