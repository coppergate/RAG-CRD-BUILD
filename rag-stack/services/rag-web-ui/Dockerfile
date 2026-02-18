FROM golang:1.24-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git

# Cache modules layer
COPY go.mod .
RUN go mod download

# Copy sources and build
COPY . .
RUN go get go.opentelemetry.io/otel \
    go.opentelemetry.io/otel/sdk \
    go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp \
    go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
RUN go mod tidy
RUN go build -debug-trace=trace.json -o rag-web-ui cmd/ui/main.go

FROM alpine:latest

WORKDIR /app
COPY --from=builder /app/rag-web-ui .

RUN apk add --no-cache ca-certificates

CMD ["./rag-web-ui"]
