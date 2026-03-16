#!/bin/bash
# bootstrap-orchestrator.sh - Build the Build Orchestrator image using a raw Kaniko Job
# Run on hierophant

set -e

REPO_DIR="/mnt/hegemon-share/share/code/complete-build/rag-stack"
NAMESPACE="build-pipeline"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
VERSION="latest"
REGISTRY="registry.hierocracy.home:5000"
INTERNAL_REGISTRY="registry.container-registry.svc.cluster.local:5000"
ORCHESTRATOR_TAG="${ORCHESTRATOR_TAG:-$VERSION}"

source "$REPO_DIR/../scripts/journal-helper.sh"

echo "--- 1. Packaging Build Orchestrator sources ---"
TARBALL="orchestrator-bootstrap.tar.gz"
# We only need the orchestrator folder for the bootstrap
cd "$REPO_DIR/services/build-orchestrator"
tar -czf "$SAFE_TMP_DIR/$TARBALL" .
cd - > /dev/null

echo "--- 2. Uploading sources to S3 ---"
# Create a temporary uploader pod
$KUBECTL run s3-bootstrap-uploader -n $NAMESPACE --image=$INTERNAL_REGISTRY/amazon/aws-cli:2.34.4 --overrides='
{
  "spec": {
    "containers": [{
      "name": "uploader",
      "image": "'"$INTERNAL_REGISTRY"'/amazon/aws-cli:2.34.4",
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

$KUBECTL wait --for=condition=Ready pod/s3-bootstrap-uploader -n $NAMESPACE --timeout=60s
# Stream tarball directly to S3 via stdin to avoid 'tar' dependency in the container
# Capture pre-signed URL to avoid AWS SDK credential issues in Kaniko
PRESIGNED_URL=$(cat "$SAFE_TMP_DIR/$TARBALL" | $KUBECTL exec -i -n $NAMESPACE s3-bootstrap-uploader -- \
  sh -c "aws --endpoint-url http://\$S3_ENDPOINT s3 cp - s3://\$BUCKET_NAME/$TARBALL > /dev/null && aws --endpoint-url http://\$S3_ENDPOINT s3 presign s3://\$BUCKET_NAME/$TARBALL --expires-in 3600")
$KUBECTL delete pod s3-bootstrap-uploader -n $NAMESPACE --now

echo "--- 3. Launching Bootstrap Kaniko Job ---"
# Apply the CA ConfigMap first
$KUBECTL apply -f "$REPO_DIR/infrastructure/build-pipeline/registry-ca-cm.yaml"

# Delete existing job if it exists (for retries)
$KUBECTL delete job kaniko-bootstrap-orchestrator -n $NAMESPACE --ignore-not-found=true
# We define the job inline to avoid needing a separate file for the one-shot bootstrap
cat <<EOF | $KUBECTL apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: kaniko-bootstrap-orchestrator
  namespace: $NAMESPACE
spec:
  template:
    spec:
      initContainers:
      - name: fetch-context
        image: $INTERNAL_REGISTRY/busybox:1.37.0
        command: ["sh", "-c"]
        args: ["wget -O /workspace/context.tar.gz \"$PRESIGNED_URL\" && tar -xzof /workspace/context.tar.gz -C /workspace && rm /workspace/context.tar.gz"]
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
          runAsNonRoot: true
          runAsUser: 1000
          seccompProfile:
            type: RuntimeDefault
        volumeMounts:
        - name: workspace
          mountPath: /workspace
      containers:
      - name: kaniko
        image: $INTERNAL_REGISTRY/martizih/kaniko:v1.27.0
        args:
        - "--dockerfile=Dockerfile"
        - "--context=dir:///workspace"
        - "--destination=$INTERNAL_REGISTRY/build-orchestrator:$ORCHESTRATOR_TAG"
        - "--destination=$INTERNAL_REGISTRY/build-orchestrator:latest"
        securityContext:
          allowPrivilegeEscalation: true
        volumeMounts:
        - name: workspace
          mountPath: /workspace
        - name: registry-ca
          mountPath: /kaniko/ssl/certs/ca-certificates.crt
          subPath: ca.crt
      volumes:
      - name: workspace
        emptyDir: {}
      - name: registry-ca
        configMap:
          name: registry-ca
      restartPolicy: Never
  backoffLimit: 0
EOF

echo "--- 4. Waiting for Bootstrap Build to complete ---"
until [[ "$($KUBECTL get job kaniko-bootstrap-orchestrator -n $NAMESPACE -o jsonpath='{.status.succeeded}')" == "1" ]]; do
    if [[ "$($KUBECTL get job kaniko-bootstrap-orchestrator -n $NAMESPACE -o jsonpath='{.status.failed}')" == "1" ]]; then
        echo "ERROR: Bootstrap build failed. Check logs: kubectl logs -n $NAMESPACE -l job-name=kaniko-bootstrap-orchestrator"
        exit 1
    fi
    echo "Building... (polling in 10s)"
    sleep 10
done

echo "Bootstrap complete. Build Orchestrator image is in the registry (tag=$ORCHESTRATOR_TAG)."
# Cleanup the bootstrap job
$KUBECTL delete job kaniko-bootstrap-orchestrator -n $NAMESPACE
rm "$SAFE_TMP_DIR/$TARBALL"
