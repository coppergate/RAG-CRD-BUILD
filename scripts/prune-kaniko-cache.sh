#!/usr/bin/env bash
set -Eeuo pipefail

REGISTRY="registry.hierocracy.home:5000"
REPO="kaniko-cache"
TLS_FLAG="--tls-verify=false"

echo "Listing tags for $REPO..."
TAGS=$(skopeo list-tags $TLS_FLAG "docker://$REGISTRY/$REPO" | jq -r '.Tags[]')

for tag in $TAGS; do
    echo "Deleting tag $tag..."
    # We need the digest to delete
    DIGEST=$(skopeo inspect $TLS_FLAG "docker://$REGISTRY/$REPO:$tag" | jq -r '.Digest')
    skopeo delete $TLS_FLAG "docker://$REGISTRY/$REPO@$DIGEST"
done

echo "Done."
