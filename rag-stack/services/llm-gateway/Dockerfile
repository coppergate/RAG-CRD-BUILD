# Go toolchain pinned for reproducibility and to satisfy upstream deps (genproto >= go1.25)
FROM golang:1.25-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev git

# Cache modules layer
COPY common/ /common/
COPY llm-gateway/go.mod llm-gateway/go.sum ./
RUN CGO_ENABLED=0 go mod download

# Copy sources and build
COPY llm-gateway/ .
RUN CGO_ENABLED=0 go get google.golang.org/genproto/googleapis/api@latest google.golang.org/genproto/googleapis/rpc@latest
RUN CGO_ENABLED=0 go mod tidy
RUN CGO_ENABLED=0 go build -v -o llm-gateway cmd/gateway/main.go

FROM alpine:latest

WORKDIR /app
COPY --from=builder /app/llm-gateway .

RUN apk add --no-cache ca-certificates

CMD ["./llm-gateway"]
