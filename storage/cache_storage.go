package storage

import (
	"context"
	"errors"
	"time"

	"github.com/goccy/go-json"
	"github.com/redis/go-redis/v9"
)

const redisPrefix = "eth-indexer:cache:"

type RedisCacheStorage struct {
	rc *redis.Client
}

func NewRedisCacheStorage(rc *redis.Client) *RedisCacheStorage {
	return &RedisCacheStorage{rc: rc}
}

func (cs *RedisCacheStorage) Get(ctx context.Context, key string) (string, bool, error) {
	s, err := cs.rc.Get(ctx, redisPrefix+key).Result()
	if err != nil && errors.Is(redis.Nil, err) {
		return "", true, nil
	}
	return s, false, err
}

func (cs *RedisCacheStorage) Set(
	ctx context.Context,
	key string,
	value interface{},
	ttl int64,
) error {
	key = redisPrefix + key
	raw, err := json.Marshal(value)
	if err != nil {
		return err
	}
	exp := time.Duration(ttl) * time.Second
	return cs.rc.Set(ctx, key, string(raw), exp).Err()
}
