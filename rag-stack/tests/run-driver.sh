#!/bin/bash
# run-driver.sh - Run the Go E2E test driver natively

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd "$DIR"
go run .
