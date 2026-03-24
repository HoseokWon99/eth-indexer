# Build stage
FROM golang:1.24-alpine AS builder

WORKDIR /app
ENV GOTOOLCHAIN=auto

COPY services/kafka-router/go.mod services/kafka-router/go.sum* ./
RUN go mod download

COPY services/kafka-router/ .

RUN CGO_ENABLED=0 GOOS=linux go build -o /kafka-router .

# Runtime stage
FROM alpine:3.19

COPY --from=builder /kafka-router /kafka-router

CMD ["/kafka-router"]
