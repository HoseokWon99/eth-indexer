package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"eth-indexer.dev/libs/config"
	"github.com/ethereum/go-ethereum/accounts/abi"
	ethcommon "github.com/ethereum/go-ethereum/common"
)

type WorkerConfig struct {
	Name              string
	ABI               *abi.ABI
	ContractAddresses []ethcommon.Address
	EventNames        []string
}

type IndexerOptions struct {
	RpcUrl            string
	Workers           []WorkerConfig
	ConfirmedAfter    uint64
	OffsetBlockNumber uint64
	StatusFilePath    string
}

type ApiOptions struct {
	Port int
}

type Options struct {
	Indexer     *IndexerOptions
	Postgres    *config.PostgresOptions
	Mongo       *config.MongoOptions
	API         *ApiOptions
	StorageType string // "postgres" (default) or "mongo"
}

// LoadOptions loads all service configuration from environment variables.
func LoadOptions() (*Options, error) {
	ixOpts, err := loadIndexerFromEnv()
	if err != nil {
		return nil, fmt.Errorf("indexer indexer: %w", err)
	}
	pgOpts, err := config.LoadPostgresFromEnv()
	if err != nil {
		return nil, fmt.Errorf("database indexer: %w", err)
	}
	apiOpts, err := loadApiOptions()
	if err != nil {
		return nil, fmt.Errorf("api indexer: %w", err)
	}
	storageType := config.GetEnv("STORAGE_TYPE", "postgres")
	return &Options{
		Indexer:     ixOpts,
		Postgres:    pgOpts,
		Mongo:       config.LoadMongoFromEnv(),
		API:         apiOpts,
		StorageType: storageType,
	}, nil
}

func loadApiOptions() (*ApiOptions, error) {
	portStr := config.GetEnv("API_PORT", "8080")
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return nil, fmt.Errorf("invalid API_PORT %q: %w", portStr, err)
	}
	return &ApiOptions{Port: port}, nil
}

// loadIndexerFromEnv reads all IndexerOptions fields from environment variables.
//
// Required vars: ETHEREUM_RPC_URL, INDEXER_WORKER_0_ABI_PATH, INDEXER_WORKER_0_CONTRACT_ADDRESSES, INDEXER_WORKER_0_EVENT_NAMES.
// Optional vars: INDEXER_CONFIRMED_AFTER (default 12), INDEXER_OFFSET_BLOCK_NUMBER (default 0),
// INDEXER_STATUS_FILE_PATH (default /var/lib/eth-indexer/state/indexer-state.json).
func loadIndexerFromEnv() (*IndexerOptions, error) {
	rpcURL := os.Getenv("ETHEREUM_RPC_URL")
	if rpcURL == "" {
		return nil, fmt.Errorf("ETHEREUM_RPC_URL is required")
	}

	workers, err := loadWorkerConfigs()
	if err != nil {
		return nil, err
	}

	confirmedAfter, err := getUint64Env("INDEXER_CONFIRMED_AFTER", "12")
	if err != nil {
		return nil, err
	}

	offsetBlockNumber, err := getUint64Env("INDEXER_OFFSET_BLOCK_NUMBER", "0")
	if err != nil {
		return nil, err
	}

	statusFilePath := config.GetEnv("INDEXER_STATUS_FILE_PATH", "/var/lib/indexer/state.json")

	return &IndexerOptions{
		RpcUrl:            rpcURL,
		Workers:           workers,
		ConfirmedAfter:    confirmedAfter,
		OffsetBlockNumber: offsetBlockNumber,
		StatusFilePath:    statusFilePath,
	}, nil
}

// loadWorkerConfigs scans numbered env vars INDEXER_WORKER_N_* until ABI_PATH is missing.
func loadWorkerConfigs() ([]WorkerConfig, error) {
	var workers []WorkerConfig
	for i := 0; ; i++ {
		prefix := fmt.Sprintf("INDEXER_WORKER_%d_", i)
		abiPath := os.Getenv(prefix + "ABI_PATH")
		if abiPath == "" {
			break
		}

		parsedABI, err := loadABIFromPath(abiPath)
		if err != nil {
			return nil, fmt.Errorf("worker %d: %w", i, err)
		}

		addresses, err := loadContractAddressesFromEnv(prefix + "CONTRACT_ADDRESSES")
		if err != nil {
			return nil, fmt.Errorf("worker %d: %w", i, err)
		}

		eventNames, err := loadEventNamesFromEnv(prefix + "EVENT_NAMES")
		if err != nil {
			return nil, fmt.Errorf("worker %d: %w", i, err)
		}

		name := os.Getenv(prefix + "NAME")
		if name == "" {
			name = fmt.Sprintf("worker-%d", i)
		}

		workers = append(workers, WorkerConfig{
			Name:              name,
			ABI:               parsedABI,
			ContractAddresses: addresses,
			EventNames:        eventNames,
		})
	}
	if len(workers) == 0 {
		return nil, fmt.Errorf("no workers configured: set INDEXER_WORKER_0_ABI_PATH at minimum")
	}
	return workers, nil
}

// loadABIFromPath reads and parses the JSON ABI file at the given path.
func loadABIFromPath(path string) (*abi.ABI, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("failed to open ABI file %q: %w", path, err)
	}
	defer f.Close()

	parsedABI, err := abi.JSON(f)
	if err != nil {
		return nil, fmt.Errorf("failed to parse ABI file %q: %w", path, err)
	}
	return &parsedABI, nil
}

// loadContractAddressesFromEnv parses a comma-separated list of hex addresses from the given env var.
func loadContractAddressesFromEnv(envVar string) ([]ethcommon.Address, error) {
	raw := os.Getenv(envVar)
	if raw == "" {
		return nil, fmt.Errorf("%s is required", envVar)
	}
	parts := strings.Split(raw, ",")
	addresses := make([]ethcommon.Address, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		if !ethcommon.IsHexAddress(p) {
			return nil, fmt.Errorf("invalid contract address %q in %s", p, envVar)
		}
		addresses = append(addresses, ethcommon.HexToAddress(p))
	}
	if len(addresses) == 0 {
		return nil, fmt.Errorf("%s must contain at least one address", envVar)
	}
	return addresses, nil
}

// loadEventNamesFromEnv parses a comma-separated list of event names from the given env var.
func loadEventNamesFromEnv(envVar string) ([]string, error) {
	raw := os.Getenv(envVar)
	if raw == "" {
		return nil, fmt.Errorf("%s is required", envVar)
	}
	parts := strings.Split(raw, ",")
	names := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			names = append(names, p)
		}
	}
	if len(names) == 0 {
		return nil, fmt.Errorf("%s must contain at least one event name", envVar)
	}
	return names, nil
}

func getUint64Env(key, defaultVal string) (uint64, error) {
	val := config.GetEnv(key, defaultVal)
	n, err := strconv.ParseUint(val, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid %s %q: %w", key, val, err)
	}
	return n, nil
}
