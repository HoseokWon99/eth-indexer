package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"time"

	"eth-indexer.dev/services/indexer/core"
)

type Server struct {
	indexer *core.Indexer
	port    int
}

func NewServer(indexer *core.Indexer, port int) *Server {
	return &Server{indexer: indexer, port: port}
}

func (s *Server) Start(ctx context.Context) error {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.health)
	mux.HandleFunc("/state", s.state)
	server := &http.Server{
		Addr:    fmt.Sprintf(":%d", s.port),
		Handler: mux,
	}
	serverErr := make(chan error, 1)
	go func() {
		log.Printf("Starting indexer HTTP server on port %d", s.port)
		if err := server.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()
	select {
	case <-ctx.Done():
	case err := <-serverErr:
		return err
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return server.Shutdown(shutdownCtx)
}

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
}

func (s *Server) state(w http.ResponseWriter, _ *http.Request) {
	state, err := s.indexer.State()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(state); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}
