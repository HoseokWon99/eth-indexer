FORK_URL ?= https://eth.llamarpc.com

.PHONY: anvil-fork \
	build build-indexer build-api-server build-dashboard build-all \
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

build-dashboard:
	cd services/dashboard && go build -o ../../bin/dashboard .

build-all: build-indexer build-api-server build-dashboard

# Alias for backwards compatibility
build: build-all

# Run services
run-indexer:
	cd services/indexer && go run .

run-api-server:
	gcd services/api-server && go run .

run-dashboard:
	cd services/dashboard && go run .

# Tidy all modules
tidy-all:
	cd libs/common && go mod tidy
	cd services/indexer && go mod tidy
	cd services/api-server && go mod tidy
	cd services/dashboard && go mod tidy

# Run Go unit tests
test:
	cd services/indexer && go test -v ./...

test-unit:
	cd services/indexer && go test -v ./...

# Build docker images
docker-build:
	docker build -f services/indexer/Dockerfile -t eth-indexer:latest .
	docker build -f services/api-server/Dockerfile -t eth-api-server:latest .
	docker build -f services/dashboard/Dockerfile -t eth-dashboard:latest .

# Clean build artifacts
clean:
	rm -rf bin/
	go clean

# Install dependencies
deps:
	go work sync

# Run linter
lint:
	golangci-lint run

test-anvil-up:
	docker compose -f test/anvil/docker-compose.anvil.yml up -d

test-anvil-down:
	docker compose -f test/anvil/docker-compose.anvil.yml down

test-db-up:
	docker compose -f test/database/docker-compose.db.yml up -d

test-db-down:
	docker compose -f test/database/docker-compose.db.yml down

# Kafka test environment
test-kafka-up:
	docker compose -f test/kafka/docker-compose.kafka.yml up -d

test-kafka-down:
	docker compose -f test/kafka/docker-compose.kafka.yml down

test-debezium-up:
	docker compose -f test/database/docker-compose.debezium.yml up -d

test-debezium-down:
	docker compose -f test/database/docker-compose.debezium.yml down

local-up: local-down
	docker compose -f docker-compose.local.yml up --build -d

local-down:
	docker compose -f docker-compose.local.yml down

test-e2e:
	cd test/e2e && npm test

contracts-build:
	@cd test/contracts && forge build

contracts-test:
	@cd test/contracts && forge test

abi-json: contracts-build
	@mkdir -p test/abi
	@for contract in TestToken StakingPool UniswapPool; do \
		jq '.abi' test/contracts/out/$$contract.sol/$$contract.json > test/abi/$$contract.json; \
		echo "Generated test/abi/$$contract.json"; \
	done

generate-events:
	@bash scripts/anvil/generate-events.sh

# Minikube cluster
cluster-up:
	@bash scripts/k8s/cluster-up.sh

cluster-down:
	@bash scripts/k8s/cluster-down.sh

test-cluster:
	@bash scripts/k8s/test-cluster.sh ./indexer-config.test.json

# Show help
help:
	@echo "Available targets:"
	@echo "  build-indexer     - Build indexer binary"
	@echo "  build-api-server  - Build api-server binary"
	@echo "  build-dashboard   - Build dashboard binary"
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
