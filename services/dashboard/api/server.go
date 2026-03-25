package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"time"

	"eth-indexer.dev/services/dashboard/sse"
	"eth-indexer.dev/services/dashboard/static"
)

type Server struct {
	hub          *sse.Hub
	topics       []string
	apiServerURL string
	port         int
}

func NewServer(hub *sse.Hub, topics []string, apiServerURL string, port int) *Server {
	return &Server{
		hub:          hub,
		topics:       topics,
		apiServerURL: apiServerURL,
		port:         port,
	}
}

func (s *Server) Start(ctx context.Context) error {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	mux.HandleFunc("GET /config", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{ //nolint:errcheck
			"topics":       s.topics,
			"apiServerUrl": s.apiServerURL,
		})
	})

	mux.Handle("GET /events", sse.Handler(s.hub))

	mux.Handle("GET /", http.FileServer(http.FS(static.FS)))

	srv := &http.Server{
		Addr:    fmt.Sprintf(":%d", s.port),
		Handler: mux,
	}

	serverErr := make(chan error, 1)
	go func() {
		log.Printf("dashboard HTTP server listening on :%d", s.port)
		if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
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
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return err
	}
	log.Println("dashboard HTTP server stopped")
	return nil
}
