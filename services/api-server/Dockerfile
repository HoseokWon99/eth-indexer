# Build stage
FROM golang:1.24-alpine AS builder

WORKDIR /app
ENV GOTOOLCHAIN=auto

# Copy workspace and module files for dependency caching
COPY libs/common/go.mod libs/common/
COPY libs/config/go.mod libs/config/go.sum* libs/config/
COPY services/api-server/go.mod services/api-server/go.sum* services/api-server/
RUN go work init libs/common libs/config services/api-server
RUN go mod tidy -C services/api-server

# Copy source
COPY libs/common/ libs/common/
COPY libs/config/ libs/config/
COPY services/api-server/ services/api-server/

RUN CGO_ENABLED=0 GOOS=linux go build -o /api-server ./services/api-server

# Runtime stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /root/

COPY --from=builder /api-server .

EXPOSE 8080

CMD ["./api-server"]
