package common

import "time"

type EventRecord struct {
	Topic           string                 `json:"topic"`
	ContractAddress string                 `json:"contract_address"`
	TxHash          string                 `json:"tx_hash"`
	BlockHash       string                 `json:"block_hash"`
	BlockNumber     uint64                 `json:"block_number"`
	LogIndex        uint64                 `json:"log_index"`
	Data            map[string]interface{} `json:"data"`
	Timestamp       time.Time              `json:"timestamp"`
}
