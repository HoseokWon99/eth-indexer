package api

import (
	"encoding/json"
	"eth-indexer/core"
	"eth-indexer/service"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Handler manages HTTP request handlers
type Handler struct {
	ixs    *service.IndexerService
	ss     *service.SearchService
	topics map[string]struct{}
}

// NewHandler creates a new HTTP handler
func NewHandler(
	indexerService *service.IndexerService,
	searchService *service.SearchService,
	topics []string,
) *Handler {
	handler := &Handler{
		ixs:    indexerService,
		ss:     searchService,
		topics: make(map[string]struct{}),
	}
	for _, topic := range topics {
		handler.topics[topic] = struct{}{}
	}
	return handler
}

// Health returns the health status
func (h *Handler) Health(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/text")
	if _, err := fmt.Fprint(w, "OK"); err != nil {
		log.Printf(err.Error())
		http.Error(w, "Internal server error", http.StatusInternalServerError)
	}
}

// State returns the core status
func (h *Handler) State(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(h.ixs.State()); err != nil {
		log.Printf(err.Error())
		http.Error(w, "Internal server error", http.StatusInternalServerError)
	}
}

// Search handles event search requests via GET with dot-notation query parameters
// Example: Transfer.contract_address=0x123,0x456&Transfer.block_number={"gte":1000}
// path: /search/{topic}
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

	filters, err := parseQueryString(r.URL.Query())
	if err != nil {
		http.Error(w, "Invalid query parameters: "+err.Error(), http.StatusBadRequest)
		return
	}
	// Search using the SearchService
	records, err := h.ss.SearchEventRecords(r.Context(), topic, filters)
	if err != nil {
		http.Error(w, "Search failed", http.StatusInternalServerError)
		return
	}
	resBody := SearchResponse{Count: len(records), Result: records}
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(resBody); err != nil {
		log.Printf("Encoding error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
	}
}

// parseQueryString parses filter parameters into EventRecordFilters
func parseQueryString(qs url.Values) (core.EventRecordFilters, error) {
	filters := core.EventRecordFilters{}
	// Parse contract_address (comma-separated)
	if v := qs.Get("contract_address"); len(v) > 0 {
		filters.ContractAddress = strings.Split(v, ",")
	}
	// Parse tx_hash (comma-separated)
	if v := qs.Get("tx_hash"); len(v) > 0 {
		filters.TxHash = strings.Split(v, ",")
	}
	// Parse block_hash (comma-separated)
	if v := qs.Get("block_hash"); len(v) > 0 {
		filters.BlockHash = strings.Split(v, ",")
	}
	// Parse block_number (JSON encoded ComparisonFilter)
	if v := qs.Get("block_number"); len(v) > 0 {
		blockNumber := core.ComparisonFilter[uint64]{}
		if err := json.Unmarshal([]byte(v), &blockNumber); err != nil {
			return filters, fmt.Errorf("invalid block_number format: %w", err)
		}
		filters.BlockNumber = blockNumber
	}
	// Parse log_index (comma-separated uint64s)
	if v := qs.Get("log_index"); len(v) > 0 {
		indices := strings.Split(v, ",")
		filters.LogIndex = make([]uint64, 0, len(indices))
		for _, idx := range indices {
			li, err := strconv.ParseUint(strings.TrimSpace(idx), 10, 64)
			if err != nil {
				return filters, fmt.Errorf("invalid log_index value '%s': %w", idx, err)
			}
			filters.LogIndex = append(filters.LogIndex, li)
		}
	}
	// Parse data (JSON encoded map)
	if v := qs.Get("data"); len(v) > 0 {
		data := make(map[string]interface{})
		if err := json.Unmarshal([]byte(v), &data); err != nil {
			return filters, fmt.Errorf("invalid data format: %w", err)
		}
		filters.Data = data
	}
	// Parse timestamp (JSON encoded ComparisonFilter)
	if v := qs.Get("timestamp"); len(v) > 0 {
		timestamp := core.ComparisonFilter[time.Time]{}
		if err := json.Unmarshal([]byte(v), &timestamp); err != nil {
			return filters, fmt.Errorf("invalid timestamp format: %w", err)
		}
		filters.Timestamp = timestamp
	}
	return filters, nil
}
