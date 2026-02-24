# Go toolchain pinned for reproducibility and to satisfy upstream deps (genproto >= go1.25)
FROM golang:1.25-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev git

# Cache modules layer
COPY go.mod go.sum ./
RUN go mod download

# Copy sources and build
COPY . .
RUN go get google.golang.org/genproto/googleapis/api@latest google.golang.org/genproto/googleapis/rpc@latest
RUN go mod tidy
RUN go build -debug-trace=trace.json -o db-adapter cmd/adapter/main.go

FROM alpine:latest

WORKDIR /app
COPY --from=builder /app/db-adapter .

RUN apk add --no-cache ca-certificates

CMD ["./db-adapter"]
