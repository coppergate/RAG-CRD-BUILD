# Go toolchain pinned for reproducibility and to satisfy upstream deps (genproto >= go1.25)
FROM registry.hierocracy.home:5000/golang:1.25-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev git

# Cache modules layer
COPY common/go.mod common/go.sum /common/
COPY llm-gateway/go.mod llm-gateway/go.sum ./
RUN CGO_ENABLED=0 go mod download

# Copy sources and build
COPY common/ /common/
COPY llm-gateway/ .
RUN CGO_ENABLED=0 GOFLAGS="-mod=readonly" go build -v -o llm-gateway cmd/gateway/main.go

FROM registry.hierocracy.home:5000/alpine:3.23.3

WORKDIR /app
COPY --from=builder /app/llm-gateway .

RUN apk add --no-cache ca-certificates

CMD ["./llm-gateway"]
