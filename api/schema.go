package api

import "eth-indexer/core"

// SearchResponse represents the search API response
// The response is a map where each key is the cache key (topic?querystring)
// and the value is an array of matching event records
//
// Example response:
//
//	{
//	  "Transfer?contract_address=0x123": [
//	    {
//	      "contract_address": "0x123",
//	      "tx_hash": "0xabc...",
//	      "block_number": 1000,
//	      ...
//	    }
//	  ]
//	}
type SearchResponse struct {
	Count  int                `json:"count"`
	Result []core.EventRecord `json:"result"`
}

// StateResponse represents the indexer state
type StateResponse struct {
	LatestBlock  uint64 `json:"latest_block"`
	IndexedBlock uint64 `json:"indexed_block"`
	IsRunning    bool   `json:"is_running"`
}
