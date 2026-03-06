# Go toolchain pinned for reproducibility and to satisfy upstream deps (genproto >= go1.25)
FROM golang:1.25-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev git

# Cache modules layer
COPY common/ /common/
COPY db-adapter/go.mod db-adapter/go.sum ./
RUN CGO_ENABLED=0 go mod download

# Copy sources and build
COPY db-adapter/ .
RUN CGO_ENABLED=0 go get google.golang.org/genproto/googleapis/api@latest google.golang.org/genproto/googleapis/rpc@latest
RUN CGO_ENABLED=0 go mod tidy
RUN CGO_ENABLED=0 go build -v -o db-adapter cmd/adapter/main.go

FROM alpine:latest

WORKDIR /app
COPY --from=builder /app/db-adapter .

RUN apk add --no-cache ca-certificates

CMD ["./db-adapter"]
