package scanner

import (
	"context"
	"eth-indexer/core"
	"fmt"
	"math/big"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

type EventRecordsScanner struct {
	eth               *ethclient.Client
	abi               *abi.ABI
	event             abi.Event
	topics            [][]common.Hash
	indexedInputNames []string
	contractAddresses []common.Address
}

func NewEventRecordsScanner(
	eth *ethclient.Client,
	abi *abi.ABI,
	eventName string,
	contractAddresses []common.Address,
) (*EventRecordsScanner, error) {
	event, ok := abi.Events[eventName]
	if !ok {
		return nil, fmt.Errorf("event '%s' not found in ABI", eventName)
	}
	indexedInputNames := make([]string, 0, len(event.Inputs))
	for _, input := range event.Inputs {
		if input.Indexed {
			indexedInputNames = append(indexedInputNames, input.Name)
		}
	}
	return &EventRecordsScanner{
		eth:               eth,
		abi:               abi,
		event:             event,
		topics:            [][]common.Hash{{crypto.Keccak256Hash([]byte(event.Sig))}},
		indexedInputNames: indexedInputNames,
		contractAddresses: contractAddresses,
	}, nil
}

func (ers *EventRecordsScanner) Topic0() common.Hash {
	return ers.topics[0][0]
}

func (ers *EventRecordsScanner) EventName() string {
	return ers.event.Name
}

func (ers *EventRecordsScanner) Scan(ctx context.Context, fromBlockNumber, toBlockNumber uint64) ([]core.EventRecord, error) {
	filter := ethereum.FilterQuery{
		FromBlock: new(big.Int).SetUint64(fromBlockNumber),
		ToBlock:   new(big.Int).SetUint64(toBlockNumber),
		Addresses: ers.contractAddresses,
		Topics:    ers.topics,
	}
	logs, err := ers.eth.FilterLogs(ctx, filter)
	if err != nil {
		return nil, err
	}
	records := make([]core.EventRecord, 0, len(logs))
	for _, lg := range logs {
		record, err := ers.parseLog(lg)
		if err != nil {
			fmt.Printf("Failed to parse log %d : %s", lg.Index, err.Error())
			continue
		}
		records = append(records, record)
	}
	return records, nil
}

func (ers *EventRecordsScanner) parseLog(lg types.Log) (core.EventRecord, error) {
	if err := ers.validateLog(lg); err != nil {
		return core.EventRecord{}, err
	}
	data, err := ers.extractEventData(lg)
	if err != nil {
		return core.EventRecord{}, err
	}
	return core.EventRecord{
		ContractAddress: lg.Address.Hex(),
		TxHash:          lg.TxHash.Hex(),
		BlockHash:       lg.BlockHash.Hex(),
		BlockNumber:     lg.BlockNumber,
		Data:            data,
		Timestamp:       time.Now().UTC(),
	}, nil
}

func (ers *EventRecordsScanner) validateLog(lg types.Log) error {
	if len(lg.Topics) == 0 {
		return fmt.Errorf("empty topics")
	}
	if lg.Topics[0].Cmp(ers.Topic0()) != 0 {
		return fmt.Errorf("unexpected topic %s", lg.Topics[0].Hex())
	}
	return nil
}

func (ers *EventRecordsScanner) extractEventData(lg types.Log) (map[string]interface{}, error) {
	data := make(map[string]interface{})
	for idx, topic := range lg.Topics[1:] {
		data[ers.indexedInputNames[idx]] = topic.Hex()
	}
	if err := ers.abi.UnpackIntoMap(data, ers.event.Name, lg.Data); err != nil {
		return nil, err
	}
	return data, nil
}
