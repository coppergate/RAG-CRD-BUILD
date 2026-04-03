#!/bin/bash
# build-all-on-cluster.sh - Build all RAG images using the cluster-native pipeline
# Run on hierophant

set -Eeuo pipefail

VERSION="${VERSION:-2.4.2}"
WAIT_FOR_COMPLETION="${WAIT_FOR_COMPLETION:-false}"
TRIGGER_PARALLELISM="${TRIGGER_PARALLELISM:-4}"
if [[ "${1:-}" == "--wait" ]]; then
    WAIT_FOR_COMPLETION="true"
fi

BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TRIGGER_SCRIPT="$BASE_DIR/infrastructure/build-pipeline/trigger-build.sh"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
NAMESPACE="build-pipeline"
source "$BASE_DIR/../scripts/journal-helper.sh"
REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
INTERNAL_REGISTRY="${INTERNAL_REGISTRY:-registry.container-registry.svc.cluster.local:5000}"
TOOLING_REGISTRY="${TOOLING_REGISTRY:-$INTERNAL_REGISTRY}"
BUILD_WAIT_TIMEOUT_SECONDS="${BUILD_WAIT_TIMEOUT_SECONDS:-2700}" # 45 minutes
BUILD_WAIT_POLL_SECONDS="${BUILD_WAIT_POLL_SECONDS:-15}"

services=(
    "db-adapter"
    "llm-gateway"
    "object-store-mgr"
    "qdrant-adapter"
    "rag-worker"
    "rag-explorer"
    "rag-web-ui"
    "rag-ingestion"
    "rag-test-runner"
    "rag-admin-api"
    "memory-controller"
)
job_names=()
trigger_pids=()

require_cmd() {
    local c="$1"
    command -v "$c" >/dev/null 2>&1 || {
        echo "ERROR: required command missing: $c"
        exit 1
    }
}

wait_for_image() {
    local service="$1"
    local version="$2"
    local image="docker://${REGISTRY}/${service}:${version}"
    local elapsed=0

    echo "Waiting for image availability: ${REGISTRY}/${service}:${version}"
    while [[ "$elapsed" -lt "$BUILD_WAIT_TIMEOUT_SECONDS" ]]; do
        if skopeo inspect --tls-verify=false "$image" >/dev/null 2>&1; then
            echo "Image ready: ${REGISTRY}/${service}:${version}"
            return 0
        fi
        sleep "$BUILD_WAIT_POLL_SECONDS"
        elapsed=$((elapsed + BUILD_WAIT_POLL_SECONDS))
    done

    echo "ERROR: Timed out waiting for image: ${REGISTRY}/${service}:${version}"
    return 1
}

echo "===================================================="
echo "Triggering Cluster-Native Build for all services (v$VERSION)"
echo "===================================================="

echo "--- Packaging shared source context once for all services ---"
RUN_ID="$(date +%Y%m%d%H%M%S)-$$"
TARBALL="sources-${RUN_ID}.tar.gz"
UPLOADER_POD="s3-uploader-all-${RUN_ID}"
PRESIGNED_URL=""

cleanup() {
    $KUBECTL delete pod "$UPLOADER_POD" -n "$NAMESPACE" --ignore-not-found --now >/dev/null 2>&1 || true
    rm -f "$SAFE_TMP_DIR/$TARBALL"
}
trap cleanup EXIT

cd "$BASE_DIR/services"
tar -czf "$SAFE_TMP_DIR/$TARBALL" .
cd - > /dev/null

$KUBECTL run "$UPLOADER_POD" -n "$NAMESPACE" --image="$TOOLING_REGISTRY/amazon/aws-cli:2.34.4" --overrides='
{
  "spec": {
    "containers": [{
      "name": "uploader",
      "image": "'"$TOOLING_REGISTRY"'/amazon/aws-cli:2.34.4",
      "command": ["sleep", "300"],
      "securityContext": {
        "allowPrivilegeEscalation": false,
        "capabilities": { "drop": ["ALL"] },
        "runAsNonRoot": true,
        "runAsUser": 1000,
        "seccompProfile": { "type": "RuntimeDefault" }
      },
      "envFrom": [
        {"secretRef": {"name": "build-pipeline-bucket"}},
        {"configMapRef": {"name": "build-pipeline-bucket"}}
      ],
      "env": [
        {"name": "S3_ENDPOINT", "value": "rook-ceph-rgw-ceph-object-store.rook-ceph.svc.cluster.local"},
        {"name": "AWS_REGION", "value": "us-east-1"}
      ]
    }]
  }
}' --restart=Never

if ! $KUBECTL wait --for=condition=Ready "pod/$UPLOADER_POD" -n "$NAMESPACE" --timeout=60s; then
    echo "ERROR: uploader pod did not become Ready"
    $KUBECTL -n "$NAMESPACE" describe "pod/$UPLOADER_POD" || true
    $KUBECTL -n "$NAMESPACE" logs "pod/$UPLOADER_POD" --all-containers --tail=200 || true
    exit 1
fi

PRESIGNED_URL=$(cat "$SAFE_TMP_DIR/$TARBALL" | $KUBECTL exec -i -n "$NAMESPACE" "$UPLOADER_POD" -- \
  sh -c "aws --endpoint-url http://\$S3_ENDPOINT s3 cp - s3://\$BUCKET_NAME/$TARBALL > /dev/null && aws --endpoint-url http://\$S3_ENDPOINT s3 presign s3://\$BUCKET_NAME/$TARBALL --expires-in 3600")

$KUBECTL delete pod "$UPLOADER_POD" -n "$NAMESPACE" --now >/dev/null 2>&1 || true

echo "--- Dispatching build tasks (parallelism=$TRIGGER_PARALLELISM) ---"
for service in "${services[@]}"; do
    echo "Triggering build for $service..."
    REGISTRY="$REGISTRY" TOOLING_REGISTRY="$TOOLING_REGISTRY" \
      SOURCE_TARBALL="$TARBALL" SOURCE_URL="$PRESIGNED_URL" \
      bash "$TRIGGER_SCRIPT" "$service" "$VERSION" &
    trigger_pids+=("$!")
    job_names+=("kaniko-build-${service}-${VERSION}")

    while [[ "${#trigger_pids[@]}" -ge "$TRIGGER_PARALLELISM" ]]; do
        next_pids=()
        for pid in "${trigger_pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                next_pids+=("$pid")
            else
                wait "$pid"
            fi
        done
        trigger_pids=("${next_pids[@]}")
        sleep 1
    done
done

for pid in "${trigger_pids[@]}"; do
    wait "$pid"
done

if [[ "$WAIT_FOR_COMPLETION" == "true" ]]; then
    require_cmd skopeo
    echo ""
    echo "--- Waiting for images to become available in registry ---"
    for service in "${services[@]}"; do
        if ! wait_for_image "$service" "$VERSION"; then
            echo "Recent build jobs (if any):"
            $KUBECTL get jobs -n "$NAMESPACE" -o wide || true
            echo "Recent orchestrator logs:"
            $KUBECTL logs -n "$NAMESPACE" deploy/build-orchestrator --tail=200 || true
            exit 1
        fi
    done
    echo "All service images are available in registry."
else
    echo ""
    echo "All builds triggered. Monitor progress with:"
    echo "kubectl get jobs -n build-pipeline"
fi
