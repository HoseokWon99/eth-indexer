package core

import "context"

type CacheStorage interface {
	Get(ctx context.Context, key string) (string, bool, error)
	Set(ctx context.Context, key string, value interface{}, ttl int64) error
}
