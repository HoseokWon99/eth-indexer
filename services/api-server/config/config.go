package config

import (
	"crypto/tls"
	"fmt"
	"os"
	"strconv"
	"strings"

	"eth-indexer.dev/libs/config"
	"github.com/redis/go-redis/v9"
)

type APIOptions struct {
	Port uint16
	TTL  int64
}

type RedisOptions struct {
	Host       string
	Port       uint16
	Password   string
	DB         int
	CACertPath string
}

type Options struct {
	API      *APIOptions
	Postgres *config.PostgresOptions
	Redis    *RedisOptions
	Topics   []string
}

func LoadConfig() (*Options, error) {
	apiOpts, err := loadAPIOptions()
	if err != nil {
		return nil, err
	}
	pgOpts, err := config.LoadPostgresFromEnv()
	if err != nil {
		return nil, err
	}
	redisOps, err := loadRedisOptions()
	if err != nil {
		return nil, err
	}
	return &Options{
		API:      apiOpts,
		Postgres: pgOpts,
		Redis:    redisOps,
		Topics:   loadTopics(),
	}, nil
}

func loadAPIOptions() (*APIOptions, error) {
	port, err := getUint16Env("API_PORT", "8080")
	if err != nil {
		return nil, err
	}
	ttl, err := getInt64Env("API_TTL", "60")
	if err != nil {
		return nil, err
	}
	return &APIOptions{Port: port, TTL: ttl}, nil
}

func loadRedisOptions() (*RedisOptions, error) {
	port, err := getUint16Env("REDIS_PORT", "6379")
	if err != nil {
		return nil, err
	}
	db, err := getIntEnv("REDIS_DB", "0")
	if err != nil {
		return nil, err
	}
	return &RedisOptions{
		Host:       os.Getenv("REDIS_HOST"),
		Port:       port,
		Password:   os.Getenv("REDIS_PASSWORD"),
		DB:         db,
		CACertPath: os.Getenv("REDIS_CA_CERT_PATH"),
	}, nil
}

func loadTopics() []string {
	topicsStr := os.Getenv("TOPICS")
	if topicsStr == "" {
		return nil
	}
	return strings.Split(topicsStr, ",")
}

func CreateRedisClient(options *RedisOptions) (*redis.Client, error) {
	redisConfig := &redis.Options{
		Addr:     fmt.Sprintf("%s:%d", options.Host, options.Port),
		Password: options.Password,
		DB:       options.DB,
	}
	if len(options.CACertPath) > 0 {
		certPool, err := config.CreateCertPool(options.CACertPath)
		if err != nil {
			return nil, err
		}
		redisConfig.TLSConfig = &tls.Config{
			RootCAs: certPool,
		}
	}
	return redis.NewClient(redisConfig), nil
}

func getUint16Env(key, defaultVal string) (uint16, error) {
	val := config.GetEnv(key, defaultVal)
	n, err := strconv.ParseUint(val, 10, 16)
	if err != nil {
		return 0, fmt.Errorf("invalid %s: %w", key, err)
	}
	return uint16(n), nil
}

func getInt64Env(key, defaultVal string) (int64, error) {
	val := config.GetEnv(key, defaultVal)
	n, err := strconv.ParseInt(val, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid %s: %w", key, err)
	}
	return n, nil
}

func getIntEnv(key, defaultVal string) (int, error) {
	val := config.GetEnv(key, defaultVal)
	n, err := strconv.Atoi(val)
	if err != nil {
		return 0, fmt.Errorf("invalid %s: %w", key, err)
	}
	return n, nil
}
