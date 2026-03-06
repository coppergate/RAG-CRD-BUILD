# Go toolchain pinned for reproducibility and to satisfy upstream deps (genproto >= go1.25)
FROM golang:1.25-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git

# Cache modules layer
COPY common/ /common/
COPY rag-web-ui/go.mod ./
RUN CGO_ENABLED=0 go mod download

# Copy sources and build
COPY rag-web-ui/ .
RUN CGO_ENABLED=0 go get go.opentelemetry.io/otel \
    go.opentelemetry.io/otel/sdk \
    go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp \
    go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
RUN CGO_ENABLED=0 go mod tidy
RUN CGO_ENABLED=0 go build -debug-trace=trace.json -o rag-web-ui cmd/ui/main.go

FROM alpine:latest

WORKDIR /app
COPY --from=builder /app/rag-web-ui .

RUN apk add --no-cache ca-certificates

CMD ["./rag-web-ui"]
