FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o kafka-router ./cmd/kafka-router

FROM alpine:3.19
COPY --from=builder /app/kafka-router /kafka-router
CMD ["/kafka-router"]
