package api

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// Server wraps the HTTP server with graceful shutdown
type Server struct {
	handler *Handler
	port    int
}

// NewServer creates a new API server
func NewServer(handler *Handler, port int) *Server {
	return &Server{
		handler: handler,
		port:    port,
	}
}

// Start starts the HTTP server with graceful shutdown support
func (s *Server) Start(ctx context.Context) error {
	// Set up HTTP routes
	http.HandleFunc("/health", s.handler.Health)
	http.HandleFunc("/status", s.handler.State)
	http.HandleFunc("/search/{topic}", s.handler.Search)
	// Create server
	server := &http.Server{
		Addr:    fmt.Sprintf(":%d", s.port),
		Handler: http.DefaultServeMux,
	}
	// Set up a graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	// Run server in goroutine
	serverErr := make(chan error, 1)
	go func() {
		log.Printf("Starting API server on port %d", s.port)
		if err := server.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()
	// Wait for a shutdown signal or context cancellation
	select {
	case <-sigChan:
		log.Println("Received shutdown signal")
	case <-ctx.Done():
		log.Println("Context cancelled")
	case err := <-serverErr:
		return err
	}
	// Graceful shutdown
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		return err
	}
	log.Println("Server stopped gracefully")
	return nil
}
