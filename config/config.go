package config

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/jackc/pgx"
	"github.com/redis/go-redis/v9"
)

const DefaultConfigPath = "/etc/eth-indexer/config.json"

// IndexerOptions holds indexer-specific configuration
type IndexerOptions struct {
	RpcUrl            string           `json:"rpc_url"`
	ContractAddresses []common.Address `json:"contract_addresses"`
	ABI               *abi.ABI         `json:"abi"`
	EventNames        []string         `json:"event_names"`
	ConfirmedAfter    uint64           `json:"confirmed_after"`
	OffsetBlockNumber uint64           `json:"offset_block_number"`
	StatusFilePath    string           `json:"status_file_path"`
}

// PostgresOptions holds PostgreSQL configuration
type PostgresOptions struct {
	Host           string `json:"host"`
	Port           uint16 `json:"port"`
	Database       string `json:"database"`
	User           string `json:"user"`
	Password       string `json:"password"`
	MaxConnections int    `json:"max_connections"`
	CACertPath     string `json:"ca_cert_path,omitempty"` // Optional: enables TLS if provided (AWS RDS)
}

// RedisOptions holds Redis/Valkey configuration
type RedisOptions struct {
	Host       string `json:"host"`
	Port       uint16 `json:"port"`
	Password   string `json:"password,omitempty"`
	DB         int    `json:"db"`
	CACertPath string `json:"ca_cert_path,omitempty"` // Optional: enables TLS if provided (AWS ElastiCache)
}

type ApiOptions struct {
	Port uint16 `json:"port"`
	TTL  int64  `json:"ttl"`
}

// Config holds all application configuration
type Config struct {
	API      ApiOptions      `json:"api"`
	Indexer  IndexerOptions  `json:"indexer"`
	Redis    RedisOptions    `json:"redis"`
	Postgres PostgresOptions `json:"postgres"`
}

// Load reads configuration from a JSON file
func Load(filepath string) (*Config, error) {
	// Validate filepath
	if filepath == "" {
		filepath = DefaultConfigPath
	}
	if !strings.HasSuffix(filepath, ".json") {
		return nil, fmt.Errorf("config file must be a .json file, got: %s", filepath)
	}
	// Read JSON file
	data, err := os.ReadFile(filepath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file %s: %w", filepath, err)
	}
	var result Config
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("failed to parse config JSON: %w", err)
	}
	return &result, nil
}

func CreatePgConnPool(options PostgresOptions) (*pgx.ConnPool, error) {
	pgConfig := pgx.ConnConfig{
		Host:     options.Host,
		Port:     options.Port,
		Database: options.Database,
		User:     options.User,
		Password: options.Password,
	}
	if len(options.CACertPath) > 0 {
		certPool, err := createCertPool(options.CACertPath)
		if err != nil {
			return nil, err
		}
		pgConfig.TLSConfig = &tls.Config{
			RootCAs: certPool,
		}
	}
	return pgx.NewConnPool(pgx.ConnPoolConfig{
		ConnConfig:     pgConfig,
		MaxConnections: options.MaxConnections,
	})
}

func CreateRedisClient(options RedisOptions) (*redis.Client, error) {
	redisConfig := &redis.Options{
		Addr:     fmt.Sprintf("%s:%d", options.Host, options.Port),
		Password: options.Password,
		DB:       options.DB,
	}
	if len(options.CACertPath) > 0 {
		certPool, err := createCertPool(options.CACertPath)
		if err != nil {
			return nil, err
		}
		redisConfig.TLSConfig = &tls.Config{
			RootCAs: certPool,
		}
	}
	return redis.NewClient(redisConfig), nil
}

func createCertPool(filepath string) (*x509.CertPool, error) {
	ca, err := os.ReadFile(filepath)
	if err != nil {
		return nil, err
	}
	certPool := x509.NewCertPool()
	if !certPool.AppendCertsFromPEM(ca) {
		return nil, fmt.Errorf("failed to append CA certificate")
	}
	return certPool, nil
}
