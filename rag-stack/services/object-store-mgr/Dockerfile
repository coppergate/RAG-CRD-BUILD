# Go toolchain pinned for reproducibility and to satisfy upstream deps (genproto >= go1.25)
FROM golang:1.25-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev git

# Cache modules layer
COPY common/ /common/
COPY object-store-mgr/go.mod ./
RUN CGO_ENABLED=0 go mod download

# Copy sources and build
COPY object-store-mgr/ .
RUN CGO_ENABLED=0 go mod tidy
RUN CGO_ENABLED=0 go build -v -o manager cmd/manager/main.go

FROM alpine:latest

WORKDIR /app
COPY --from=builder /app/manager .

RUN apk add --no-cache ca-certificates

CMD ["./manager"]
