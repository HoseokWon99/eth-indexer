package api

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"eth-indexer.dev/libs/common"
	"eth-indexer.dev/services/api-server/core"
	"eth-indexer.dev/services/api-server/types"
)

type Handler struct {
	ers    core.EventRecordsStorage
	cs     core.CacheStorage
	topics map[string]struct{}
}

func NewHandler(
	ers core.EventRecordsStorage,
	cs core.CacheStorage,
	topics []string,
) *Handler {
	handler := &Handler{
		ers:    ers,
		cs:     cs,
		topics: make(map[string]struct{}),
	}
	for _, topic := range topics {
		handler.topics[topic] = struct{}{}
	}
	return handler
}

func (h *Handler) Health(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/text")
	if _, err := fmt.Fprint(w, "OK"); err != nil {
		log.Printf(err.Error())
		http.Error(w, "Internal server error", http.StatusInternalServerError)
	}
}

func (h *Handler) Search(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	topic := r.PathValue("topic")
	if _, ok := h.topics[topic]; !ok {
		http.Error(w, "Topic Not Found", http.StatusNotFound)
		return
	}
	cacheKey := topic + "?" + r.URL.RawQuery
	data, expired, err := h.cs.Get(r.Context(), cacheKey)
	if err != nil {
		log.Printf("Failed to search from cache: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	if expired {
		filters, paging, err := parseQueryString(r.URL.Query())
		if err != nil {
			log.Printf("Failed to parse query string: %v", err)
			http.Error(w, "Bad request", http.StatusBadRequest)
			return
		}
		records, err := h.ers.FindAll(r.Context(), topic, filters, paging)
		if err != nil {
			log.Printf("Failed to search from storage: %v", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}
		data = types.SearchResponse{
			Count:  len(records),
			Result: records,
		}
		if err := h.cs.Set(r.Context(), cacheKey, data); err != nil {
			log.Printf("Failed to write to cache: %v", err)
		}
	}
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(data); err != nil {
		log.Printf("Encoding error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
	}
}

func parseQueryString(qs url.Values) (*types.EventRecordFilters, *common.PagingOptions[types.EventRecordCursor], error) {
	filters, err := extractFilters(qs)
	if err != nil {
		return filters, nil, err
	}
	paging, err := extractPaging(qs)
	return filters, paging, err
}

func extractFilters(qs url.Values) (*types.EventRecordFilters, error) {
	filters := types.EventRecordFilters{}
	if v := qs.Get("contract_address"); len(v) > 0 {
		filters.ContractAddress = strings.Split(v, ",")
	}
	if v := qs.Get("tx_hash"); len(v) > 0 {
		filters.TxHash = strings.Split(v, ",")
	}
	if v := qs.Get("block_hash"); len(v) > 0 {
		filters.BlockHash = strings.Split(v, ",")
	}
	if v := qs.Get("block_number"); len(v) > 0 {
		blockNumber := common.ComparisonFilter[uint64]{}
		if err := json.Unmarshal([]byte(v), &blockNumber); err != nil {
			return nil, fmt.Errorf("invalid block_number format: %w", err)
		}
		filters.BlockNumber = blockNumber
	}
	if v := qs.Get("log_index"); len(v) > 0 {
		indices := strings.Split(v, ",")
		filters.LogIndex = make([]uint64, 0, len(indices))
		for _, idx := range indices {
			li, err := strconv.ParseUint(strings.TrimSpace(idx), 10, 64)
			if err != nil {
				return nil, fmt.Errorf("invalid log_index value '%s': %w", idx, err)
			}
			filters.LogIndex = append(filters.LogIndex, li)
		}
	}
	if v := qs.Get("data"); len(v) > 0 {
		data := make(map[string]interface{})
		if err := json.Unmarshal([]byte(v), &data); err != nil {
			return nil, fmt.Errorf("invalid data format: %w", err)
		}
		filters.Data = data
	}
	if v := qs.Get("timestamp"); len(v) > 0 {
		timestamp := common.ComparisonFilter[time.Time]{}
		if err := json.Unmarshal([]byte(v), &timestamp); err != nil {
			return nil, fmt.Errorf("invalid timestamp format: %w", err)
		}
		filters.Timestamp = timestamp
	}
	return &filters, nil
}
func extractPaging(qs url.Values) (*common.PagingOptions[types.EventRecordCursor], error) {
	paging := common.PagingOptions[types.EventRecordCursor]{}
	if v := qs.Get("cursor"); len(v) > 0 {
		cursor := types.EventRecordCursor{}
		if err := json.Unmarshal([]byte(v), &cursor); err != nil {
			return nil, fmt.Errorf("invalid cursor format: %w", err)
		}
		paging.Cursor = &cursor
	}
	if v := qs.Get("limit"); len(v) > 0 {
		limit, err := strconv.ParseUint(v, 10, 64)
		if err != nil {
			return nil, fmt.Errorf("invalid limit format: %w", err)
		}
		paging.Limit = limit
	}
	return &paging, nil
}
