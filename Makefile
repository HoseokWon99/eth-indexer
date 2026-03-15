.PHONY: build run test docker-build docker-up docker-down clean test-env-up test-env-down test-env-clean test-unit test-integration test-e2e test-all install-foundry contracts-build contracts-test

# Build the application
build:
	go build -o bin/eth-indexer ./cmd/eth-indexer

# Run the application (requires .env file)
run:
	go run ./cmd/eth-indexer

# Run Go unit tests
test:
	go test -v ./...

test-unit:
	go test -v ./...

# Build docker image
docker-build:
	docker build -t eth-indexer:latest .

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
	go mod download
	go mod tidy

# Format code
fmt:
	go fmt ./...

# Run linter
lint:
	golangci-lint run

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

# Show help
help:
	@echo "Available targets:"
	@echo "  build             - Build the binary"
	@echo "  run               - Run the application"
	@echo "  test              - Run Go unit tests"
	@echo "  docker-build      - Build Docker image"
	@echo "  docker-up         - Start services with docker-compose"
	@echo "  docker-down       - Stop docker-compose services"
	@echo "  clean             - Remove build artifacts"
	@echo "  deps              - Install and tidy dependencies"
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
