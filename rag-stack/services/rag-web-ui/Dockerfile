# Go toolchain pinned for reproducibility and to satisfy upstream deps (genproto >= go1.25)
FROM registry.hierocracy.home:5000/golang:1.25-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git

# Cache modules layer
COPY common/ /common/
COPY rag-web-ui/go.mod rag-web-ui/go.sum ./
RUN CGO_ENABLED=0 go mod download

# Copy sources and build
COPY rag-web-ui/ .
RUN CGO_ENABLED=0 GOFLAGS="-mod=readonly" go build -v -o rag-web-ui cmd/ui/main.go

FROM registry.hierocracy.home:5000/alpine:3.23.3

WORKDIR /app
COPY --from=builder /app/rag-web-ui .

RUN apk add --no-cache ca-certificates

CMD ["./rag-web-ui"]
