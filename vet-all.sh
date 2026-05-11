#!/bin/bash
set -e
for d in rag-stack/services/*/ ; do
    if [ -f "$d/go.mod" ]; then
        echo "Vetting $d ..."
        cd "$d"
        go vet ./...
        echo "Building $d (dry-run) ..."
        go build -o /dev/null ./...
        cd - > /dev/null
    fi
done
