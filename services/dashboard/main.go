package main

import (
	"context"
	"log"
	"os/signal"
	"syscall"

	"eth-indexer.dev/services/dashboard/api"
	"eth-indexer.dev/services/dashboard/config"
	"eth-indexer.dev/services/dashboard/consumer"
	"eth-indexer.dev/services/dashboard/sse"
)

func main() {
	opts, err := config.LoadOptions()
	if err != nil {
		log.Fatalf("configuration error: %v", err)
	}

	brokers := []string{opts.Kafka.BootstrapServers}

	log.Printf("dashboard starting: consuming %s", opts.Kafka.SourceTopic)

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()

	hub := sse.NewHub()
	go hub.Run()

	c := consumer.NewConsumer(brokers, opts.Kafka.SourceTopic, hub)
	defer c.Close()
	go c.Run(ctx)

	srv := api.NewServer(hub, opts.UI.Topics, opts.UI.APIServerURL, opts.UI.Port)
	if err := srv.Start(ctx); err != nil {
		log.Fatalf("HTTP server error: %v", err)
	}

	log.Println("dashboard stopped.")
}
