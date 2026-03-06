#!/bin/bash
# build-all-on-cluster.sh - Build all RAG images using the cluster-native pipeline
# Run on hierophant

set -Eeuo pipefail

VERSION="${VERSION:-1.5.7}"
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

services=(
    "db-adapter"
    "llm-gateway"
    "object-store-mgr"
    "qdrant-adapter"
    "rag-worker"
    "rag-web-ui"
    "rag-ingestion"
)
job_names=()
trigger_pids=()

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

$KUBECTL run "$UPLOADER_POD" -n "$NAMESPACE" --image=amazon/aws-cli --overrides='
{
  "spec": {
    "containers": [{
      "name": "uploader",
      "image": "amazon/aws-cli",
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

$KUBECTL wait --for=condition=Ready "pod/$UPLOADER_POD" -n "$NAMESPACE" --timeout=60s

PRESIGNED_URL=$(cat "$SAFE_TMP_DIR/$TARBALL" | $KUBECTL exec -i -n "$NAMESPACE" "$UPLOADER_POD" -- \
  sh -c "aws --endpoint-url http://\$S3_ENDPOINT s3 cp - s3://\$BUCKET_NAME/$TARBALL > /dev/null && aws --endpoint-url http://\$S3_ENDPOINT s3 presign s3://\$BUCKET_NAME/$TARBALL --expires-in 3600")

$KUBECTL delete pod "$UPLOADER_POD" -n "$NAMESPACE" --now >/dev/null 2>&1 || true

echo "--- Dispatching build tasks (parallelism=$TRIGGER_PARALLELISM) ---"
for service in "${services[@]}"; do
    echo "Triggering build for $service..."
    SOURCE_TARBALL="$TARBALL" SOURCE_URL="$PRESIGNED_URL" bash "$TRIGGER_SCRIPT" "$service" "$VERSION" &
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
    echo ""
    echo "--- Waiting for builds to complete ---"
    for job in "${job_names[@]}"; do
        echo "Waiting for $job..."
        if ! $KUBECTL wait -n "$NAMESPACE" --for=condition=complete "job/$job" --timeout=45m; then
            echo "ERROR: Build job did not complete: $job"
            $KUBECTL get job "$job" -n "$NAMESPACE" -o wide || true
            $KUBECTL logs -n "$NAMESPACE" -l "job-name=$job" --tail=200 || true
            exit 1
        fi
    done
    echo "All builds completed successfully."
else
    echo ""
    echo "All builds triggered. Monitor progress with:"
    echo "kubectl get jobs -n build-pipeline"
fi
