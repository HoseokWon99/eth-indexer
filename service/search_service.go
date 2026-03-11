package service

import (
	"context"
	"encoding/json"
	"eth-indexer/core"
	"log"
	"slices"
	"strconv"

	"github.com/cespare/xxhash"
	"github.com/vmihailenco/msgpack/v5"
)

const cachePrefix = "cache:search:"

type cacheValue struct {
	Records []core.EventRecord `json:"records"`
}

type SearchService struct {
	eventRecordsStorage core.EventRecordsStorage
	cacheStorage        core.CacheStorage
	ttl                 int64
}

func NewSearchService(
	eventRecordsStorage core.EventRecordsStorage,
	cacheStorage core.CacheStorage,
	ttl int64,
) *SearchService {
	return &SearchService{
		eventRecordsStorage: eventRecordsStorage,
		cacheStorage:        cacheStorage,
		ttl:                 ttl,
	}
}

func (ss *SearchService) SearchEventRecords(
	ctx context.Context,
	topic string,
	filters core.EventRecordFilters,
) ([]core.EventRecord, error) {
	cacheKey, err := makeCacheKey(topic, filters)
	if err != nil {
		return nil, err
	}
	records, expired, err := ss.searchFromCache(ctx, cacheKey) // Try cache first
	if !expired && err == nil {
		return records, nil
	}
	if err != nil {
		log.Printf("[SearchService] Failed to search from cache: %v", err)
	}
	records, err = ss.eventRecordsStorage.FindAll(ctx, topic, filters)
	if err != nil {
		return nil, err
	}
	if expired { // Write cache if cache miss or expired
		err := ss.writeToCache(ctx, cacheKey, records)
		if err != nil {
			log.Printf("[SearchService] Failed to write to cache: %v", err)
		}
	}
	return records, err
}

func (ss *SearchService) searchFromCache(
	ctx context.Context,
	key string,
) ([]core.EventRecord, bool, error) {
	raw, expired, err := ss.cacheStorage.Get(ctx, key)
	if expired || err != nil {
		return nil, expired, err
	}
	data := cacheValue{}
	err = json.Unmarshal([]byte(raw), &data)
	if err != nil {
		return nil, false, err
	}
	return data.Records, false, nil
}

func (ss *SearchService) writeToCache(
	ctx context.Context,
	key string,
	records []core.EventRecord,
) error {
	raw, err := json.Marshal(cacheValue{Records: records})
	if err != nil {
		return err
	}
	return ss.cacheStorage.Set(ctx, key, raw, ss.ttl)
}

// makeCacheKey generates a compact binary hash for both cache storage
// Format: "search:topic:12345678901234567890"
func makeCacheKey(topic string, filters core.EventRecordFilters) (string, error) {
	normalized := normalizeFilters(filters)
	encoded, err := msgpack.Marshal(normalized)
	if err != nil {
		return "", err
	}
	// Hash for a compact key
	hash := xxhash.Sum64(encoded)
	return cachePrefix + topic + ":" + strconv.FormatUint(hash, 10), nil
}

// normalizeFilters ensures the same filters always produce the same cache key
func normalizeFilters(filters core.EventRecordFilters) core.EventRecordFilters {
	result := filters
	if len(filters.ContractAddress) > 0 {
		result.ContractAddress = slices.Clone(filters.ContractAddress)
		slices.Sort(result.ContractAddress)
	}
	if len(filters.TxHash) > 0 {
		result.TxHash = slices.Clone(filters.TxHash)
		slices.Sort(result.TxHash)
	}
	if len(filters.BlockHash) > 0 {
		result.BlockHash = slices.Clone(filters.BlockHash)
		slices.Sort(result.BlockHash)
	}
	if len(filters.LogIndex) > 0 {
		result.LogIndex = slices.Clone(filters.LogIndex)
		slices.Sort(result.LogIndex)
	}
	return result
}
