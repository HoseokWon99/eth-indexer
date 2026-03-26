# Build stage
FROM golang:1.24-alpine AS builder

WORKDIR /app
ENV GOTOOLCHAIN=auto

# Copy workspace and module files for dependency caching
COPY libs/common/go.mod libs/common/
COPY libs/config/go.mod libs/config/go.sum* libs/config/
COPY services/dashboard/go.mod services/dashboard/go.sum* services/dashboard/
RUN go work init libs/common libs/config services/dashboard
RUN go mod tidy -C services/dashboard

# Copy source
COPY libs/common/ libs/common/
COPY libs/config/ libs/config/
COPY services/dashboard/ services/dashboard/

RUN CGO_ENABLED=0 GOOS=linux go build -o /dashboard ./services/dashboard

# Runtime stage
FROM alpine:3.19

COPY --from=builder /dashboard .

CMD ["./dashboard"]
