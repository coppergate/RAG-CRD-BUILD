# Go toolchain pinned for reproducibility and to satisfy upstream deps (genproto >= go1.25)
FROM golang:1.25-alpine AS builder

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
RUN go build -debug-trace=trace.json -o rag-worker cmd/worker/main.go

# Final image
FROM alpine:latest

WORKDIR /app
COPY --from=builder /app/rag-worker .

# Runtime dependencies
RUN apk add --no-cache ca-certificates

CMD ["./rag-worker"]
