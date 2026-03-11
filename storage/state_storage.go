package storage

import (
	"eth-indexer/core"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/goccy/go-json"
)

type SimpleStateStorage struct {
	filepath string
	data     map[string]uint64
}

func NewSimpleStateStorage(path string) (*SimpleStateStorage, error) {
	if !strings.HasSuffix(path, ".json") {
		return nil, fmt.Errorf("state file must be a .json file, got: %s", path)
	}

	// Check if file exists
	_, err := os.Stat(path)
	if os.IsNotExist(err) {
		// Create parent directories if they don't exist
		dir := filepath.Dir(path)
		if err := os.MkdirAll(dir, 0755); err != nil {
			return nil, fmt.Errorf("failed to create parent directories: %w", err)
		}

		// Create file with empty JSON object
		emptyState := []byte("{}")
		if err := os.WriteFile(path, emptyState, 0644); err != nil {
			return nil, fmt.Errorf("failed to create state file: %w", err)
		}

		log.Printf("Created state file: %s", path)
	} else if err != nil {
		// Some other error occurred while checking the file
		return nil, fmt.Errorf("failed to check state file: %w", err)
	}

	return &SimpleStateStorage{filepath: path, data: make(map[string]uint64)}, nil
}

func (ss *SimpleStateStorage) Get() (core.State, error) {
	raw, err := os.ReadFile(ss.filepath)
	if err != nil {
		log.Printf("Failed to read state file: %v", err)
		return make(map[string]uint64), nil
	}
	data := make(map[string]any)
	err = json.Unmarshal(raw, &data)
	if err != nil {
		return nil, err
	}
	result := core.State{}
	for eventName, v := range data {
		var lastBlockNumber uint64
		switch val := v.(type) {
		case string:
			// Handle string format (backwards compatibility)
			lastBlockNumber, err = strconv.ParseUint(val, 10, 64)
			if err != nil {
				return nil, err
			}
		case float64:
			// Handle number format (default JSON unmarshaling)
			lastBlockNumber = uint64(val)
		default:
			return nil, strconv.ErrSyntax
		}
		result[eventName] = lastBlockNumber
	}
	return result, nil
}

func (ss *SimpleStateStorage) Set(state core.State) error {
	raw, err := json.Marshal(state)
	if err != nil {
		return err
	}
	return os.WriteFile(ss.filepath, raw, 0644)
}
