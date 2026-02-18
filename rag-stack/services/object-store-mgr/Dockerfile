FROM golang:1.24-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev git

# No go.mod in original source, it was being initialized in k8s
# Initialize it here
RUN go mod init app-builds/rag-s3-mgr-go
RUN go get github.com/aws/aws-sdk-go-v2
RUN go get github.com/aws/aws-sdk-go-v2/config
RUN go get github.com/aws/aws-sdk-go-v2/service/s3
RUN go get go.opentelemetry.io/otel
RUN go get go.opentelemetry.io/otel/sdk
RUN go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp

COPY . .

RUN go build -debug-trace=trace.json -o manager cmd/manager/main.go

FROM alpine:latest

WORKDIR /app
COPY --from=builder /app/manager .

RUN apk add --no-cache ca-certificates

CMD ["./manager"]
