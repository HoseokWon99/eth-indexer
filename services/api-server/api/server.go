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

type Server struct {
	handler *Handler
	port    int
}

func NewServer(handler *Handler, port int) *Server {
	return &Server{
		handler: handler,
		port:    port,
	}
}

func (s *Server) Start(ctx context.Context) error {
	http.HandleFunc("/health", s.handler.Health)
	http.HandleFunc("/search/{topic}", s.handler.Search)
	server := &http.Server{
		Addr:    fmt.Sprintf(":%d", s.port),
		Handler: http.DefaultServeMux,
	}
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	serverErr := make(chan error, 1)
	go func() {
		log.Printf("Starting API server on port %d", s.port)
		if err := server.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()
	select {
	case <-sigChan:
		log.Println("Received shutdown signal")
	case <-ctx.Done():
		log.Println("Context cancelled")
	case err := <-serverErr:
		return err
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		return err
	}
	log.Println("Server stopped gracefully")
	return nil
}
