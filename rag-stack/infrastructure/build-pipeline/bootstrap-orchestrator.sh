#!/bin/bash
# bootstrap-orchestrator.sh - Build the Build Orchestrator image using a raw Kaniko Job
# Run on hierophant

set -e

REPO_DIR="/mnt/hegemon-share/share/code/complete-build/rag-stack"
NAMESPACE="build-pipeline"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
VERSION="latest"
REGISTRY="172.20.1.26:5000"

source "$REPO_DIR/../scripts/journal-helper.sh"

echo "--- 1. Packaging Build Orchestrator sources ---"
TARBALL="orchestrator-bootstrap.tar.gz"
# We only need the orchestrator folder for the bootstrap
cd "$REPO_DIR/services/build-orchestrator"
tar -czf "$SAFE_TMP_DIR/$TARBALL" .
cd - > /dev/null

echo "--- 2. Uploading sources to S3 ---"
# Create a temporary uploader pod
$KUBECTL run s3-bootstrap-uploader -n $NAMESPACE --image=amazon/aws-cli --overrides='
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

$KUBECTL wait --for=condition=Ready pod/s3-bootstrap-uploader -n $NAMESPACE --timeout=60s
# Stream tarball directly to S3 via stdin to avoid 'tar' dependency in the container
# Capture pre-signed URL to avoid AWS SDK credential issues in Kaniko
PRESIGNED_URL=$(cat "$SAFE_TMP_DIR/$TARBALL" | $KUBECTL exec -i -n $NAMESPACE s3-bootstrap-uploader -- \
  sh -c "aws --endpoint-url http://\$S3_ENDPOINT s3 cp - s3://\$BUCKET_NAME/$TARBALL > /dev/null && aws --endpoint-url http://\$S3_ENDPOINT s3 presign s3://\$BUCKET_NAME/$TARBALL --expires-in 3600")
$KUBECTL delete pod s3-bootstrap-uploader -n $NAMESPACE --now

echo "--- 3. Launching Bootstrap Kaniko Job ---"
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
        image: busybox
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
        image: martizih/kaniko:latest
        args:
        - "--dockerfile=Dockerfile"
        - "--context=dir:///workspace"
        - "--destination=$REGISTRY/build-orchestrator:latest"
        - "--insecure"
        - "--skip-tls-verify"
        securityContext:
          allowPrivilegeEscalation: true
        volumeMounts:
        - name: workspace
          mountPath: /workspace
      volumes:
      - name: workspace
        emptyDir: {}
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

echo "Bootstrap complete. Build Orchestrator image is in the registry."
# Cleanup the bootstrap job
$KUBECTL delete job kaniko-bootstrap-orchestrator -n $NAMESPACE
rm "$SAFE_TMP_DIR/$TARBALL"
