# Build stage
FROM golang:1.24-alpine AS builder

WORKDIR /app
ENV GOTOOLCHAIN=auto

COPY services/dashboard/go.mod services/dashboard/go.sum* ./
RUN go mod download

COPY services/dashboard/ .

RUN CGO_ENABLED=0 GOOS=linux go build -o /dashboard .

# Runtime stage
FROM alpine:3.19

COPY --from=builder /dashboard /dashboard

CMD ["/dashboard"]
