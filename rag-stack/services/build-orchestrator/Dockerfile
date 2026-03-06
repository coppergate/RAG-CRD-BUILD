FROM golang:1.25-alpine AS builder
WORKDIR /app
RUN apk add --no-cache gcc musl-dev git
COPY go.mod ./
RUN go mod download
COPY . .
RUN go mod tidy
RUN CGO_ENABLED=0 go build -v -o build-orchestrator cmd/orchestrator/main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/build-orchestrator .
CMD ["./build-orchestrator"]
