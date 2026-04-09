FROM registry.hierocracy.home:5000/golang:1.25-alpine AS builder
WORKDIR /app
RUN apk add --no-cache gcc musl-dev git

# Cache modules layer
COPY common/go.mod common/go.sum /common/
COPY build-orchestrator/go.mod build-orchestrator/go.sum ./
RUN CGO_ENABLED=0 go mod download

# Copy sources and build
COPY common/ /common/
COPY build-orchestrator/ .
RUN CGO_ENABLED=0 GOFLAGS="-mod=readonly" go build -v -o build-orchestrator ./cmd/orchestrator

FROM registry.hierocracy.home:5000/alpine:3.23.3
WORKDIR /app
COPY --from=builder /app/build-orchestrator .
RUN apk add --no-cache ca-certificates
CMD ["./build-orchestrator"]
