# Build stage
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Set GOTOOLCHAIN to auto to allow downloading newer Go versions if needed
ENV GOTOOLCHAIN=auto

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o eth-indexer ./cmd/eth-indexer

# Runtime stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Copy binary from builder
COPY --from=builder /app/eth-indexer .

# Expose API port
EXPOSE 8080

CMD ["./eth-indexer"]
