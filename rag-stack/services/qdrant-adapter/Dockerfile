FROM golang:1.24-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache gcc musl-dev git

# Leverage layer cache for deps
COPY go.mod go.sum ./
RUN go mod download

# Copy the rest of the source
COPY . .
RUN go get google.golang.org/genproto/googleapis/api@latest google.golang.org/genproto/googleapis/rpc@latest
# Ensure module metadata is synchronized (writes go.sum if needed)
RUN go mod tidy

# Build
RUN go build -debug-trace=trace.json -o qdrant-adapter cmd/adapter/main.go

# Final image
FROM alpine:latest

WORKDIR /app
COPY --from=builder /app/qdrant-adapter .

# Runtime dependencies
RUN apk add --no-cache ca-certificates

CMD ["./qdrant-adapter"]
