package storage

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"eth-indexer.dev/services/api-server/types"
	"github.com/redis/go-redis/v9"
)

const redisPrefix = "eth-indexer:cache:"

type RedisCacheStorage struct {
	rc  *redis.Client
	ttl time.Duration
}

func NewRedisCacheStorage(rc *redis.Client, ttl int64) *RedisCacheStorage {
	return &RedisCacheStorage{rc: rc, ttl: time.Duration(ttl) * time.Second}
}

func (cs *RedisCacheStorage) Get(ctx context.Context, key string) (types.SearchResponse, bool, error) {
	raw, err := cs.rc.Get(ctx, redisPrefix+key).Bytes()
	if err != nil {
		if errors.Is(err, redis.Nil) {
			return types.SearchResponse{}, true, nil
		}
		return types.SearchResponse{}, false, err
	}
	result := types.SearchResponse{}
	if err = json.Unmarshal(raw, &result); err != nil {
		return types.SearchResponse{}, false, err
	}
	return result, false, nil
}

func (cs *RedisCacheStorage) Set(ctx context.Context, key string, value types.SearchResponse) error {
	raw, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return cs.rc.Set(ctx, redisPrefix+key, raw, cs.ttl).Err()
}
