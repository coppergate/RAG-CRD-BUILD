#!/bin/bash
set -e
for d in rag-stack/services/*/ ; do
    if [ -f "$d/go.mod" ]; then
        echo "Vetting $d ..."
        cd "$d"
        go vet ./...
        cd - > /dev/null
    fi
done
