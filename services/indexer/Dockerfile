# Build stage
FROM golang:1.24-alpine AS builder

WORKDIR /app
ENV GOTOOLCHAIN=auto

# Copy workspace and module files for dependency caching
COPY libs/common/go.mod libs/common/
COPY libs/config/go.mod libs/config/go.sum* libs/config/
COPY services/indexer/go.mod services/indexer/go.sum* services/indexer/
RUN go work init libs/common libs/config services/indexer
RUN go mod tidy -C services/indexer

# Copy source
COPY libs/common/ libs/common/
COPY libs/config/ libs/config/
COPY services/indexer/ services/indexer/

RUN go build -o /indexer ./services/indexer

# Runtime stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /root/

COPY --from=builder /indexer .

CMD ["./indexer"]
