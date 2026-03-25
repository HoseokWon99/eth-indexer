package config

import (
	"fmt"
	"strconv"
	"strings"

	libsconfig "eth-indexer.dev/libs/config"
)

type KafkaOptions struct {
	BootstrapServers string
	SourceTopic      string
}

type UIOptions struct {
	Port         int
	Topics       []string
	APIServerURL string
}

type Options struct {
	Kafka *KafkaOptions
	UI    *UIOptions
}

func LoadOptions() (*Options, error) {
	kafkaOpts := loadKafkaOptions()
	uiOpts, err := loadUIOptions()
	if err != nil {
		return nil, err
	}
	return &Options{Kafka: kafkaOpts, UI: uiOpts}, nil
}

func loadKafkaOptions() *KafkaOptions {
	return &KafkaOptions{
		BootstrapServers: libsconfig.GetEnv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092"),
		SourceTopic:      libsconfig.GetEnv("SOURCE_TOPIC", "eth-indexer.public.event_records"),
	}
}

func loadUIOptions() (*UIOptions, error) {
	portStr := libsconfig.GetEnv("UI_PORT", "8090")
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return nil, fmt.Errorf("invalid UI_PORT %q: %w", portStr, err)
	}
	return &UIOptions{
		Port:         port,
		Topics:       loadTopics(),
		APIServerURL: libsconfig.GetEnv("API_SERVER_URL", "http://api-server"),
	}, nil
}

func loadTopics() []string {
	raw := libsconfig.GetEnv("TOPICS", "Transfer,Approval")
	parts := strings.Split(raw, ",")
	topics := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			topics = append(topics, p)
		}
	}
	return topics
}
