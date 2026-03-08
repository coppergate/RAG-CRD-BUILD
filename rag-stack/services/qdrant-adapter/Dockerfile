# Go toolchain pinned for reproducibility and to satisfy upstream deps (genproto >= go1.25)
FROM registry.hierocracy.home:5000/golang:1.25-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache gcc musl-dev git

# Leverage layer cache for deps
COPY common/ /common/
COPY qdrant-adapter/go.mod qdrant-adapter/go.sum ./
RUN CGO_ENABLED=0 go mod download

# Copy the rest of the source
COPY qdrant-adapter/ .

# Build
RUN CGO_ENABLED=0 GOFLAGS="-mod=readonly" go build -v -o qdrant-adapter cmd/adapter/main.go

# Final image
FROM registry.hierocracy.home:5000/alpine:3.23.3

WORKDIR /app
COPY --from=builder /app/qdrant-adapter .

# Runtime dependencies
RUN apk add --no-cache ca-certificates

CMD ["./qdrant-adapter"]
