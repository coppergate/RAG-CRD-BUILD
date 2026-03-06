#!/bin/bash
# trigger-build.sh - Trigger cluster-native build from local sources
# Run on hierophant

set -e

SERVICE="${1}"
VERSION="${2:-1.5.7}"
REPO_DIR="/mnt/hegemon-share/share/code/complete-build/rag-stack"
NAMESPACE="build-pipeline"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

source "$REPO_DIR/../scripts/journal-helper.sh"

if [[ -z "$SERVICE" ]]; then
    echo "Usage: $0 <service-name> [version]"
    exit 1
fi

echo "--- 1. Packaging sources for $SERVICE ---"
TARBALL="sources-$(date +%s).tar.gz"
# Pack 'services' folder so Kaniko sees 'common/' and the target service
cd "$REPO_DIR/services"
tar -czf "$SAFE_TMP_DIR/$TARBALL" .
cd - > /dev/null

echo "--- 2. Uploading sources to S3 ---"
# Create a temporary uploader pod that has the S3 bucket access
# Using a more restricted security context to avoid PodSecurity violations
$KUBECTL run s3-uploader -n $NAMESPACE --image=amazon/aws-cli --overrides='
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

# Wait for uploader to be ready
$KUBECTL wait --for=condition=Ready pod/s3-uploader -n $NAMESPACE --timeout=60s

# Stream tarball directly to S3 via stdin to avoid 'tar' dependency in the container
# Capture pre-signed URL to avoid AWS SDK credential issues in Kaniko
PRESIGNED_URL=$(cat "$SAFE_TMP_DIR/$TARBALL" | $KUBECTL exec -i -n $NAMESPACE s3-uploader -- \
  sh -c "aws --endpoint-url http://\$S3_ENDPOINT s3 cp - s3://\$BUCKET_NAME/$TARBALL > /dev/null && aws --endpoint-url http://\$S3_ENDPOINT s3 presign s3://\$BUCKET_NAME/$TARBALL --expires-in 3600")

# Cleanup uploader pod
$KUBECTL delete pod s3-uploader -n $NAMESPACE --now

echo "--- 3. Triggering Orchestrator via Pulsar ---"
# Construct the task JSON
TASK_JSON=$(cat <<EOF
{
  "service_name": "$SERVICE",
  "version": "$VERSION",
  "dockerfile_path": "$SERVICE/Dockerfile",
  "source_tarball": "$TARBALL",
  "source_url": "$PRESIGNED_URL",
  "registry": "172.20.1.26:5000"
}
EOF
)

# Use pulsar-admin from an existing pulsar pod to send the message
PULSAR_NAMESPACE="apache-pulsar"
# Wait for the toolset pod to be ready if it exists (or wait for it to appear)
echo "Waiting for Pulsar toolset pod in $PULSAR_NAMESPACE..."
until $KUBECTL get pods -n $PULSAR_NAMESPACE -l component=toolset -o jsonpath='{.items[0].metadata.name}' >/dev/null 2>&1; do
    echo "Pulsar toolset pod not found yet. Sleeping 10s..."
    sleep 10
done

PULSAR_POD=$($KUBECTL get pods -n $PULSAR_NAMESPACE -l component=toolset -o jsonpath='{.items[0].metadata.name}')
$KUBECTL wait --for=condition=Ready pod/$PULSAR_POD -n $PULSAR_NAMESPACE --timeout=60s

$KUBECTL exec -n $PULSAR_NAMESPACE "$PULSAR_POD" -- \
  /pulsar/bin/pulsar-client produce persistent://public/default/build-tasks -m "$TASK_JSON"

echo "Build triggered for $SERVICE:$VERSION"
echo "Check Kaniko logs: $KUBECTL get jobs -n $NAMESPACE"
rm "$SAFE_TMP_DIR/$TARBALL"
