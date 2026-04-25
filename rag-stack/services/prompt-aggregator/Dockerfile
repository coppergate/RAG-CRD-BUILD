# Go toolchain pinned for reproducibility
FROM registry.hierocracy.home:5000/golang:1.25-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache gcc musl-dev git

# Leverage layer cache for deps
COPY common/go.mod common/go.sum /common/
COPY prompt-aggregator/go.mod prompt-aggregator/go.sum ./
RUN CGO_ENABLED=0 go mod download

# Copy the rest of the source
COPY common/ /common/
COPY prompt-aggregator/ .

# Build
RUN CGO_ENABLED=0 go build -v -o aggregator cmd/aggregator/main.go

# Final image
FROM registry.hierocracy.home:5000/alpine:3.23.3

WORKDIR /app
COPY --from=builder /app/aggregator .

# Runtime dependencies
RUN apk add --no-cache ca-certificates

CMD ["./aggregator"]
