FROM registry.hierocracy.home:5000/golang:1.25-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev git

# Copy shared common package
COPY common/ /common/

# Copy the service source
COPY rag-admin-api/ .

# Since we don't have a go.mod yet, initialize it if it doesn't exist or use the one from source
# For the build pipeline, we expect go.mod to be present in the service directory
RUN go mod init app-builds/rag-admin-api || true
RUN go mod tidy

# Build
RUN CGO_ENABLED=0 go build -v -o rag-admin-api cmd/admin-api/main.go

# Final image
FROM registry.hierocracy.home:5000/alpine:3.23.3

WORKDIR /app
COPY --from=builder /app/rag-admin-api .

RUN apk add --no-cache ca-certificates

CMD ["./rag-admin-api"]
