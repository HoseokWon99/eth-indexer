package storage

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"eth-indexer.dev/services/indexer/core"
)

type SimpleStateStorage struct {
	filename string
	state    core.State
}

func NewSimpleStateStorage(
	filename string,
	eventNames []string,
	offsetBlockNumber uint64,
) (*SimpleStateStorage, error) {
	if !strings.HasSuffix(filename, ".json") {
		return nil, fmt.Errorf("state file must be a .json file, got: %s", filename)
	}
	ss := &SimpleStateStorage{filename: filename, state: core.State{}}
	if err := ss.init(eventNames, offsetBlockNumber); err != nil {
		return nil, err
	}
	return ss, nil
}

func (ss *SimpleStateStorage) GetLastBlockNumber(eventName string) (uint64, error) {
	blockNumber, ok := ss.state[eventName]
	if !ok {
		return 0, fmt.Errorf("unknown event name: %s", eventName)
	}
	return blockNumber, nil
}

func (ss *SimpleStateStorage) SetLastBlockNumber(eventName string, blockNumber uint64) error {
	_, ok := ss.state[eventName]
	if !ok {
		return fmt.Errorf("unknown event name: %s", eventName)
	}
	ss.state[eventName] = blockNumber
	return nil
}

func (ss *SimpleStateStorage) Get() (core.State, error) {
	result := core.State{}
	for k, v := range ss.state {
		result[k] = v
	}
	return result, nil
}

func (ss *SimpleStateStorage) Save() error {
	raw, err := json.Marshal(ss.state)
	if err != nil {
		return err
	}
	return os.WriteFile(ss.filename, raw, 0644)
}

func (ss *SimpleStateStorage) init(eventNames []string, offsetBlockNumber uint64) error {
	if err := createFileIfNotExists(ss.filename); err != nil {
		return err
	}
	state, err := readState(ss.filename)
	if err != nil {
		return err
	}
	for _, eventName := range eventNames {
		lastBlockNumber, ok := state[eventName]
		if !ok {
			lastBlockNumber = offsetBlockNumber
		}
		ss.state[eventName] = lastBlockNumber
	}
	return nil
}

func createFileIfNotExists(filename string) error {
	_, err := os.Stat(filename)
	if os.IsNotExist(err) {
		dir := filepath.Dir(filename)
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("failed to create parent directories: %w", err)
		}
		emptyState := []byte("{}")
		if err := os.WriteFile(filename, emptyState, 0644); err != nil {
			return fmt.Errorf("failed to create state file: %w", err)
		}
		log.Printf("Created state file: %s", filename)
	} else if err != nil {
		return fmt.Errorf("failed to check state file: %w", err)
	}
	return nil
}

func readState(filename string) (core.State, error) {
	raw, err := os.ReadFile(filename)
	if err != nil {
		return nil, fmt.Errorf("failed to read state file: %w", err)
	}
	result := core.State{}
	if err := json.Unmarshal(raw, &result); err != nil {
		return nil, fmt.Errorf("failed to parse state file: %w", err)
	}
	return result, nil
}
