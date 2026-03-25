package consumer

import (
	"context"
	"encoding/json"
	"log"

	"eth-indexer.dev/services/dashboard/sse"

	"github.com/segmentio/kafka-go"
)

// Consumer reads from the CDC source topic and fans messages into an SSE hub.
type Consumer struct {
	reader *kafka.Reader
	hub    *sse.Hub
}

// NewConsumer creates a Consumer that reads from sourceTopic.
func NewConsumer(brokers []string, sourceTopic string, hub *sse.Hub) *Consumer {
	return &Consumer{
		reader: kafka.NewReader(kafka.ReaderConfig{
			Brokers:     brokers,
			Topic:       sourceTopic,
			GroupID:     "event-dashboard",
			StartOffset: kafka.LastOffset,
			MinBytes:    1,
			MaxBytes:    10e6,
		}),
		hub: hub,
	}
}

// Run reads messages until ctx is cancelled.
func (c *Consumer) Run(ctx context.Context) {
	log.Printf("consumer: subscribing to %s", c.reader.Config().Topic)
	for {
		msg, err := c.reader.FetchMessage(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			log.Printf("consumer: fetch error: %v", err)
			continue
		}

		var row struct {
			Topic string `json:"topic"`
		}
		if err := json.Unmarshal(msg.Value, &row); err != nil || row.Topic == "" {
			c.reader.CommitMessages(ctx, msg) //nolint:errcheck
			continue
		}

		c.hub.Broadcast(msg.Value)

		if err := c.reader.CommitMessages(ctx, msg); err != nil && ctx.Err() == nil {
			log.Printf("consumer: commit error: %v", err)
		}
	}
}

// Close closes the underlying Kafka reader.
func (c *Consumer) Close() {
	if err := c.reader.Close(); err != nil {
		log.Printf("consumer: close error: %v", err)
	}
}
