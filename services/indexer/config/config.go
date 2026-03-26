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

type IndexerOptions struct {
	RpcUrl            string
	ContractAddresses []ethcommon.Address
	ABI               *abi.ABI
	EventNames        []string
	ConfirmedAfter    uint64
	OffsetBlockNumber uint64
	StatusFilePath    string
}

type ApiOptions struct {
	Port int
}

type Options struct {
	Indexer  *IndexerOptions
	Postgres *config.PostgresOptions
	API      *ApiOptions
}

// LoadOptions loads all service configuration from environment variables.
func LoadOptions() (*Options, error) {
	ixOpts, err := loadIndexerFromEnv()
	if err != nil {
		return nil, fmt.Errorf("indexer indexer: %w", err)
	}
	pgOpts, err := config.LoadPostgresFromEnv()
	if err != nil {
		return nil, fmt.Errorf("postgres indexer: %w", err)
	}
	apiOpts, err := loadApiOptions()
	if err != nil {
		return nil, fmt.Errorf("api indexer: %w", err)
	}
	return &Options{Indexer: ixOpts, Postgres: pgOpts, API: apiOpts}, nil
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
// Required vars: RPC_URL, CONTRACT_ADDRESSES, ABI_PATH, EVENT_NAMES.
// Optional vars: CONFIRMED_AFTER (default 12), OFFSET_BLOCK_NUMBER (default 0),
// STATUS_FILE_PATH (default /var/lib/eth-indexer/state/indexer-state.json).
func loadIndexerFromEnv() (*IndexerOptions, error) {
	rpcURL := os.Getenv("ETHEREUM_RPC_URL")
	if rpcURL == "" {
		return nil, fmt.Errorf("ETHEREUM_RPC_URL is required")
	}

	contractAddresses, err := loadContractAddresses()
	if err != nil {
		return nil, err
	}

	parsedABI, err := loadABIFromFile()
	if err != nil {
		return nil, err
	}

	eventNames, err := loadEventNames()
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
		ContractAddresses: contractAddresses,
		ABI:               parsedABI,
		EventNames:        eventNames,
		ConfirmedAfter:    confirmedAfter,
		OffsetBlockNumber: offsetBlockNumber,
		StatusFilePath:    statusFilePath,
	}, nil
}

// loadContractAddresses parses CONTRACT_ADDRESSES as a comma-separated list of hex addresses.
func loadContractAddresses() ([]ethcommon.Address, error) {
	raw := os.Getenv("INDEXER_CONTRACT_ADDRESSES")
	if raw == "" {
		return nil, fmt.Errorf("INDEXER_CONTRACT_ADDRESSES is required")
	}
	parts := strings.Split(raw, ",")
	addresses := make([]ethcommon.Address, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		if !ethcommon.IsHexAddress(p) {
			return nil, fmt.Errorf("invalid contract address %q in CONTRACT_ADDRESSES", p)
		}
		addresses = append(addresses, ethcommon.HexToAddress(p))
	}
	if len(addresses) == 0 {
		return nil, fmt.Errorf("CONTRACT_ADDRESSES must contain at least one address")
	}
	return addresses, nil
}

// loadABIFromFile reads ABI_PATH from the environment and parses the JSON ABI file at that path.
func loadABIFromFile() (*abi.ABI, error) {
	abiPath := os.Getenv("INDEXER_ABI_PATH")
	if abiPath == "" {
		return nil, fmt.Errorf("INDEXER_ABI_PATH is required")
	}
	f, err := os.Open(abiPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open ABI file %q: %w", abiPath, err)
	}
	defer f.Close()

	parsedABI, err := abi.JSON(f)
	if err != nil {
		return nil, fmt.Errorf("failed to parse ABI file %q: %w", abiPath, err)
	}
	return &parsedABI, nil
}

// loadEventNames parses EVENT_NAMES as a comma-separated list of event names.
func loadEventNames() ([]string, error) {
	raw := os.Getenv("INDEXER_EVENT_NAMES")
	if raw == "" {
		return nil, fmt.Errorf("INDEXER_EVENT_NAMES is required")
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
		return nil, fmt.Errorf("EVENT_NAMES must contain at least one event name")
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
