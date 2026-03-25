package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/segmentio/kafka-go"
)

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	brokers := []string{env("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")}
	sourceTopic := env("SOURCE_TOPIC", "eth-indexer.public.event_records")
	destPrefix := env("DEST_TOPIC_PREFIX", "eth-indexer.events")

	log.Printf("dashboard starting: %s → %s.*", sourceTopic, destPrefix)

	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:     brokers,
		Topic:       sourceTopic,
		GroupID:     "eth-event-router",
		StartOffset: kafka.FirstOffset,
		MinBytes:    1,
		MaxBytes:    10e6,
	})
	defer func(reader *kafka.Reader) {
		if err := reader.Close(); err != nil {
			log.Fatalf("failed to close reader: %v", err)
		}
	}(reader)

	writers := make(map[string]*kafka.Writer)
	defer func(writers map[string]*kafka.Writer) {
		for _, w := range writers {
			if err := w.Close(); err != nil {
				log.Fatalf("failed to close writer: %v", err)
			}
		}
	}(writers)

	writerFor := func(topic string) *kafka.Writer {
		if w, ok := writers[topic]; ok {
			return w
		}
		w := &kafka.Writer{
			Addr:                   kafka.TCP(brokers...),
			Topic:                  topic,
			AllowAutoTopicCreation: true,
			Balancer:               &kafka.LeastBytes{},
		}
		writers[topic] = w
		return w
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()

	for {
		msg, err := reader.FetchMessage(ctx)
		if err != nil {
			if ctx.Err() != nil {
				break
			}
			log.Printf("fetch error: %v", err)
			continue
		}

		var row map[string]any
		if err := json.Unmarshal(msg.Value, &row); err != nil {
			log.Printf("unmarshal error: %v — skipping", err)
			reader.CommitMessages(ctx, msg) //nolint:errcheck
			continue
		}

		eventType, _ := row["topic"].(string)
		if eventType == "" {
			eventType = "unknown"
		}

		dest := fmt.Sprintf("%s.%s", destPrefix, eventType)
		w := writerFor(dest)

		if err := w.WriteMessages(ctx, kafka.Message{Value: msg.Value}); err != nil {
			if ctx.Err() != nil {
				break
			}
			log.Printf("write error → %s: %v", dest, err)
			continue
		}

		if err := reader.CommitMessages(ctx, msg); err != nil && ctx.Err() == nil {
			log.Printf("commit error: %v", err)
		}
	}

	log.Println("dashboard stopped.")
}
