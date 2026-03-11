.PHONY: build run test docker-build docker-up docker-down clean

# Build the application
build:
	go build -o bin/eth-indexer ./cmd/eth-indexer

# Run the application (requires .env file)
run:
	go run ./cmd/eth-indexer

# Run tests
test:
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

# Show help
help:
	@echo "Available targets:"
	@echo "  build        - Build the binary"
	@echo "  run          - Run the application"
	@echo "  test         - Run tests"
	@echo "  docker-build - Build Docker image"
	@echo "  docker-up    - Start services with docker-compose"
	@echo "  docker-down  - Stop docker-compose services"
	@echo "  clean        - Remove build artifacts"
	@echo "  deps         - Install and tidy dependencies"
	@echo "  fmt          - Format code"
	@echo "  lint         - Run linter"
