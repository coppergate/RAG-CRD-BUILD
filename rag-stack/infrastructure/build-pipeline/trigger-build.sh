#!/bin/bash
# trigger-build.sh - Trigger cluster-native build from local sources
# Run on hierophant

set -Eeuo pipefail

SERVICE="${1:-}"
VERSION="${2:-${VERSION:-}}"
REPO_DIR="/mnt/hegemon-share/share/code/complete-build/rag-stack"

# Source of truth for versioning
if [[ -z "$VERSION" ]]; then
    if [[ -f "$REPO_DIR/../CURRENT_VERSION" ]]; then
        if jq . "$REPO_DIR/../CURRENT_VERSION" >/dev/null 2>&1; then
            VERSION=$(jq -r ".\"$SERVICE\".version // \"1.0.0\"" "$REPO_DIR/../CURRENT_VERSION")
        else
            VERSION=$(cat "$REPO_DIR/../CURRENT_VERSION" | tr -d '[:space:]')
        fi
    else
        VERSION="1.0.0"
    fi
fi
export VERSION
NAMESPACE="build-pipeline"
KUBECTL="/home/k8s/kube/kubectl"
REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
INTERNAL_REGISTRY="${INTERNAL_REGISTRY:-registry.container-registry.svc.cluster.local:5000}"
TOOLING_REGISTRY="${TOOLING_REGISTRY:-$INTERNAL_REGISTRY}"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

source "$REPO_DIR/../scripts/journal-helper.sh"

if [[ -z "$SERVICE" ]]; then
    echo "Usage: $0 <service-name> [version]"
    exit 1
fi

SHARED_SOURCE_URL="${SOURCE_URL:-}"
SHARED_SOURCE_TARBALL="${SOURCE_TARBALL:-}"
CREATED_TARBALL="false"
PRESIGNED_URL="$SHARED_SOURCE_URL"
TARBALL="$SHARED_SOURCE_TARBALL"
UPLOADER_POD="s3-uploader-${SERVICE}-$$"

cleanup() {
    $KUBECTL delete pod "$UPLOADER_POD" -n "$NAMESPACE" --ignore-not-found --now >/dev/null 2>&1 || true
    if [[ "$CREATED_TARBALL" == "true" ]]; then
        rm -f "$SAFE_TMP_DIR/$TARBALL"
    fi
}
trap cleanup EXIT

if [[ -z "$PRESIGNED_URL" || -z "$TARBALL" ]]; then
    echo "--- 1. Packaging sources for $SERVICE ---"
    TARBALL="sources-$(date +%s)-$$.tar.gz"
    CREATED_TARBALL="true"
    # Pack 'services' folder so Kaniko sees 'common/' and the target service
    cd "$REPO_DIR/services"
    tar -czf "$SAFE_TMP_DIR/$TARBALL" .
    cd - > /dev/null

    echo "--- 2. Uploading sources to S3 ---"
    # Create a temporary uploader pod that has the S3 bucket access
    # Using a more restricted security context to avoid PodSecurity violations
    $KUBECTL run "$UPLOADER_POD" -n "$NAMESPACE" --image="${TOOLING_REGISTRY}/amazon/aws-cli:2.34.4" --overrides='
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

    # Wait for uploader to be ready
    if ! $KUBECTL wait --for=condition=Ready "pod/$UPLOADER_POD" -n "$NAMESPACE" --timeout=60s; then
        echo "ERROR: uploader pod did not become Ready"
        $KUBECTL -n "$NAMESPACE" describe "pod/$UPLOADER_POD" || true
        $KUBECTL -n "$NAMESPACE" logs "pod/$UPLOADER_POD" --all-containers --tail=200 || true
        exit 1
    fi

    # Stream tarball directly to S3 via stdin to avoid 'tar' dependency in the container
    # Capture pre-signed URL to avoid AWS SDK credential issues in Kaniko
    PRESIGNED_URL=$(cat "$SAFE_TMP_DIR/$TARBALL" | $KUBECTL exec -i -n "$NAMESPACE" "$UPLOADER_POD" -- \
      sh -c "aws --endpoint-url http://\$S3_ENDPOINT s3 cp - s3://\$BUCKET_NAME/$TARBALL > /dev/null && aws --endpoint-url http://\$S3_ENDPOINT s3 presign s3://\$BUCKET_NAME/$TARBALL --expires-in 3600")

    # Cleanup uploader pod early
    $KUBECTL delete pod "$UPLOADER_POD" -n "$NAMESPACE" --now >/dev/null 2>&1 || true
else
    echo "--- 1. Reusing shared source context for $SERVICE ---"
fi

echo "--- 3. Triggering Orchestrator via Pulsar ---"
# Escape JSON string values without external deps (jq/python).
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Construct the task JSON as a single line.
TASK_JSON=$(printf '{"service_name":"%s","version":"%s","dockerfile_path":"%s","source_tarball":"%s","source_url":"%s","registry":"%s"}' \
    "$(json_escape "$SERVICE")" \
    "$(json_escape "$VERSION")" \
    "$(json_escape "$SERVICE/Dockerfile")" \
    "$(json_escape "$TARBALL")" \
    "$(json_escape "$PRESIGNED_URL")" \
    "$(json_escape "$REGISTRY")")

# Use pulsar-admin from an existing pulsar pod to send the message
PULSAR_NAMESPACE="apache-pulsar"
PULSAR_WAIT_SECONDS="${PULSAR_TOOL_POD_WAIT_SECONDS:-600}"
PULSAR_POD=""
elapsed=0
while [[ "$elapsed" -lt "$PULSAR_WAIT_SECONDS" ]]; do
    for sel in "component=toolset" "app.kubernetes.io/component=toolset" "component=broker" "app.kubernetes.io/component=broker"; do
        PULSAR_POD=$($KUBECTL get pods -n "$PULSAR_NAMESPACE" -l "$sel" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
        if [[ -n "$PULSAR_POD" ]]; then
            break
        fi
    done
    if [[ -z "$PULSAR_POD" ]]; then
        PULSAR_POD=$($KUBECTL get pods -n "$PULSAR_NAMESPACE" -o name 2>/dev/null | grep -E 'toolset|broker' | head -n1 | cut -d/ -f2 || true)
    fi
    if [[ -n "$PULSAR_POD" ]]; then
        break
    fi
    echo "Pulsar admin pod not found yet. Sleeping 10s..."
    sleep 10
    elapsed=$((elapsed + 10))
done

if [[ -z "$PULSAR_POD" ]]; then
    echo "ERROR: Could not find a toolset/broker pod in namespace $PULSAR_NAMESPACE after ${PULSAR_WAIT_SECONDS}s"
    $KUBECTL get pods -n "$PULSAR_NAMESPACE" -o wide || true
    $KUBECTL get events -n "$PULSAR_NAMESPACE" --sort-by=.lastTimestamp | tail -n 60 || true
    exit 1
fi

$KUBECTL wait --for=condition=Ready "pod/$PULSAR_POD" -n "$PULSAR_NAMESPACE" --timeout=120s

TASK_B64="$(printf '%s' "$TASK_JSON" | base64 -w0)"
$KUBECTL exec -n "$PULSAR_NAMESPACE" "$PULSAR_POD" -- sh -lc "
set -eu
TMP_MSG=\$(mktemp)
printf '%s' '$TASK_B64' | base64 -d > \"\$TMP_MSG\"
/pulsar/bin/pulsar-client produce persistent://public/default/build-tasks -f \"\$TMP_MSG\"
rm -f \"\$TMP_MSG\"
"

echo "Build triggered for $SERVICE:$VERSION"
echo "Check Kaniko logs: $KUBECTL get jobs -n $NAMESPACE"
