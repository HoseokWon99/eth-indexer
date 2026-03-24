FORK_URL ?= https://eth.llamarpc.com

.PHONY: anvil-fork \
	build build-indexer build-api-server build-kafka-router build-all \
	run-indexer run-api-server \
	test test-unit test-integration test-e2e test-all \
	docker-build docker-up docker-down clean \
	test-env-up test-env-down test-env-clean \
	install-foundry contracts-build contracts-test \
	tidy-all fmt lint \
	cluster-up cluster-down test-cluster

# Build individual services
build-indexer:
	cd services/indexer && go build -o ../../bin/indexer .

build-api-server:
	cd services/api-server && go build -o ../../bin/api-server .

build-kafka-router:
	cd services/kafka-router && go build -o ../../bin/kafka-router .

build-all: build-indexer build-api-server build-kafka-router

# Alias for backwards compatibility
build: build-all

# Run services
run-indexer:
	cd services/indexer && go run .

run-api-server:
	cd services/api-server && go run .

# Tidy all modules
tidy-all:
	cd libs/common && go mod tidy
	cd services/indexer && go mod tidy
	cd services/api-server && go mod tidy
	cd services/kafka-router && go mod tidy

# Run Go unit tests
test:
	cd services/indexer && go test -v ./...

test-unit:
	cd services/indexer && go test -v ./...

# Build docker images
docker-build:
	docker build -f services/indexer/Dockerfile -t eth-indexer:latest .
	docker build -f services/api-server/Dockerfile -t eth-api-server:latest .
	docker build -f services/kafka-router/Dockerfile -t eth-kafka-router:latest .

# Start docker-compose services
docker-up:
	docker-compose up -d

# Stop docker-compose services
docker-down:
	docker-compose down

# Clean build artifacts
clean:
	rm -rf bin/
	go clean

# Install dependencies
deps:
	go work sync

# Format code
fmt:
	cd libs/common && go fmt ./...
	cd services/indexer && go fmt ./...
	cd services/api-server && go fmt ./...
	cd services/kafka-router && go fmt ./...

# Run linter
lint:
	golangci-lint run

# Fork Ethereum mainnet locally with Anvil
anvil-fork:
	anvil --host 0.0.0.0 --block-time 1 --fork-url ${FORK_URL}

# Kafka test environment
kafka-up:
	docker compose -f test/kafka/docker-compose.kafka.yml up -d

kafka-down:
	docker compose -f test/kafka/docker-compose.kafka.yml down

# Test environment management
test-env-up:
	@bash scripts/test/setup-test-env.sh

test-env-down:
	@docker-compose -f docker-compose.test.yml down

test-env-clean:
	@bash scripts/test/teardown-test-env.sh

# Testing targets
test-integration:
	@cd test && npm test

test-e2e: test-env-clean test-env-up test-integration test-env-down

test-all: test-unit test-e2e

# Contract targets
install-foundry:
	@echo "Installing Foundry..."
	@curl -L https://foundry.paradigm.xyz | bash
	@echo "Run 'foundryup' to complete installation"

contracts-build:
	@cd test/contracts && forge build

contracts-test:
	@cd test/contracts && forge test

# Start monitoring stack (Kafka, Debezium, Prometheus, Grafana)
monitoring-up:
	docker-compose up -d kafka kafka-connect debezium-init kafka-router kafka-exporter prometheus grafana

# Stop monitoring stack
monitoring-down:
	docker-compose stop kafka kafka-connect debezium-init kafka-router kafka-exporter prometheus grafana

# Minikube cluster
cluster-up:
	@bash scripts/k8s/cluster-up.sh

cluster-down:
	@bash scripts/k8s/cluster-down.sh

test-cluster:
	@bash scripts/k8s/test-cluster.sh ./indexer-config.test.json

generate-events:
	@bash scripts/anvil/generate-events.sh

# Show help
help:
	@echo "Available targets:"
	@echo "  build-indexer     - Build indexer binary"
	@echo "  build-api-server  - Build api-server binary"
	@echo "  build-kafka-router- Build kafka-router binary"
	@echo "  build-all         - Build all service binaries"
	@echo "  run-indexer       - Run indexer service"
	@echo "  run-api-server    - Run api-server service"
	@echo "  tidy-all          - Tidy all modules and sync workspace"
	@echo "  test              - Run Go unit tests"
	@echo "  docker-build      - Build all Docker images"
	@echo "  docker-up         - Start services with docker-compose"
	@echo "  docker-down       - Stop docker-compose services"
	@echo "  clean             - Remove build artifacts"
	@echo "  deps              - Sync workspace"
	@echo "  fmt               - Format code"
	@echo "  lint              - Run linter"
	@echo ""
	@echo "Test Environment:"
	@echo "  test-env-up       - Start Anvil test environment"
	@echo "  test-env-down     - Stop test environment"
	@echo "  test-env-clean    - Clean up test environment completely"
	@echo ""
	@echo "Testing:"
	@echo "  test-unit         - Run Go unit tests"
	@echo "  test-integration  - Run Jest integration tests (requires env running)"
	@echo "  test-e2e          - Full E2E: setup, test, teardown"
	@echo "  test-all          - Run all tests (unit + E2E)"
	@echo ""
	@echo "Contracts:"
	@echo "  install-foundry   - Install Foundry CLI"
	@echo "  contracts-build   - Build contracts with forge"
	@echo "  contracts-test    - Run contract tests with forge"
