#!/bin/bash
# run-driver.sh - Run the Go E2E test driver using Podman

# Get the directory where the script is located
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

podman run --rm \
    -v "$DIR":/app:Z \
    -w /app \
    golang:1.24-alpine \
    go run main.go
