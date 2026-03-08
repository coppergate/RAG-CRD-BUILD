FROM registry.hierocracy.home:5000/golang:1.25-alpine AS builder
WORKDIR /app
RUN apk add --no-cache gcc musl-dev git
COPY go.mod ./
COPY go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOFLAGS="-mod=readonly" go build -v -o build-orchestrator cmd/orchestrator/main.go

FROM registry.hierocracy.home:5000/alpine:3.23.3
WORKDIR /app
COPY --from=builder /app/build-orchestrator .
CMD ["./build-orchestrator"]
