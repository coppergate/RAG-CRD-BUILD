# Go toolchain pinned for reproducibility and to satisfy upstream deps (genproto >= go1.25)
FROM registry.hierocracy.home:5000/golang:1.25-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev git

# Cache modules layer
COPY common/ /common/
COPY db-adapter/go.mod db-adapter/go.sum ./
RUN CGO_ENABLED=0 go mod download

# Copy sources and build
COPY db-adapter/ .
RUN CGO_ENABLED=0 GOFLAGS="-mod=readonly" go build -v -o db-adapter cmd/adapter/main.go

FROM registry.hierocracy.home:5000/alpine:3.23.3

WORKDIR /app
COPY --from=builder /app/db-adapter .

RUN apk add --no-cache ca-certificates

CMD ["./db-adapter"]
