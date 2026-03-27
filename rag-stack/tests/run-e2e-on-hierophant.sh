#!/usr/bin/env bash
set -euo pipefail

# E2E test runner for hierophant host
# - Runs Kubernetes job-based integration tests
# - Runs Go E2E driver via Podman
# - Stores logs under /mnt/hegemon-share/share/code/_KUBERNETES_BUILD/ai-changes/logs

LOG_ROOT="${LOG_ROOT:-/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/ai-changes/logs}"
TS=$(date +%Y%m%d-%H%M%S)
OUT_DIR="${LOG_ROOT}/e2e-${TS}"
mkdir -p "$OUT_DIR"

NAMESPACE="rag-system"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
VERSION="${VERSION:-2.2.0}"

echo "[INFO] Preflight: Checking connectivity to hierophant and cluster..."
# 1. Ping hierophant
if ! ping -c 1 -W 2 192.168.1.101 >/dev/null 2>&1; then
  echo "[ERROR] hierophant (192.168.1.101) is not reachable via ping."
  exit 1
fi

# 2. Check Kubernetes API with retries
MAX_RETRIES=5
RETRY_COUNT=0
until "$KUBECTL" cluster-info >/dev/null 2>&1; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "[ERROR] Kubernetes API is not reachable after $MAX_RETRIES attempts."
    exit 1
  fi
  echo "[WAIT] Kubernetes API not ready, retrying in 10s ($RETRY_COUNT/$MAX_RETRIES)..."
  sleep 10
done
echo "[OK] Connectivity verified."

echo "[INFO] Logs will be saved to: ${OUT_DIR}"

if [ ! -x "$KUBECTL" ]; then
  echo "[ERROR] Expected kubectl at $KUBECTL but not found or not executable" | tee -a "${OUT_DIR}/job.log"
  exit 1
fi

# Show kubectl client version
"$KUBECTL" version --client | tee "${OUT_DIR}/kubectl-version.txt"

# 1) Refresh tests ConfigMap
echo "[STEP] Refresh tests ConfigMap" | tee -a "${OUT_DIR}/job.log"
"$KUBECTL" -n "$NAMESPACE" delete configmap rag-integration-tests --ignore-not-found | tee -a "${OUT_DIR}/job.log"
"$KUBECTL" -n "$NAMESPACE" create configmap rag-integration-tests \
  --from-file=/mnt/hegemon-share/share/code/complete-build/rag-stack/tests/integration_test.py \
  --from-file=/mnt/hegemon-share/share/code/complete-build/rag-stack/tests/context_verification.py \
  --from-file=/mnt/hegemon-share/share/code/complete-build/rag-stack/tests/pulsar_crud_test.py \
  --from-file=/mnt/hegemon-share/share/code/complete-build/rag-stack/tests/test_contracts.py \
  --from-file=/mnt/hegemon-share/share/code/complete-build/rag-stack/tests/recursive_rag_test.py \
  --from-file=/mnt/hegemon-share/share/code/complete-build/rag-stack/tests/seed_qdrant_context.py \
  --from-file=/mnt/hegemon-share/share/code/complete-build/rag-stack/tests/sad_path_test.py \
  --from-file=/mnt/hegemon-share/share/code/complete-build/rag-stack/tests/ingestion_isolation.py \
  --from-file=/mnt/hegemon-share/share/code/complete-build/rag-stack/tests/cleanup_test_data.py | tee -a "${OUT_DIR}/job.log"

# 2) Run Cleanup Job
echo "[STEP] Apply cleanup job" | tee -a "${OUT_DIR}/job.log"
"$KUBECTL" -n "$NAMESPACE" delete job rag-test-cleanup --ignore-not-found | tee -a "${OUT_DIR}/job.log"
RENDERED_CLEANUP="/tmp/rag-test-cleanup-${VERSION}.yaml"
sed "s|:2.0.0|:${VERSION}|g" /mnt/hegemon-share/share/code/complete-build/rag-stack/tests/cleanup-job.yaml > "$RENDERED_CLEANUP"
"$KUBECTL" apply -f "$RENDERED_CLEANUP" | tee -a "${OUT_DIR}/job.log"
rm -f "$RENDERED_CLEANUP"

echo "[STEP] Wait for cleanup job to complete" | tee -a "${OUT_DIR}/job.log"
"$KUBECTL" -n "$NAMESPACE" wait --for=condition=complete job/rag-test-cleanup --timeout=120s || echo "[WARN] Cleanup job timed out or failed." | tee -a "${OUT_DIR}/job.log"

# 3) Launch the test job
echo "[STEP] Apply test job" | tee -a "${OUT_DIR}/job.log"
"$KUBECTL" -n "$NAMESPACE" delete job rag-integration-test --ignore-not-found | tee -a "${OUT_DIR}/job.log"
RENDERED_JOB="/tmp/rag-integration-test-${VERSION}.yaml"
sed "s|:__VERSION__|:${VERSION}|g" /mnt/hegemon-share/share/code/complete-build/rag-stack/tests/test-job.yaml > "$RENDERED_JOB"
"$KUBECTL" apply -f "$RENDERED_JOB" | tee -a "${OUT_DIR}/job.log"
rm -f "$RENDERED_JOB"

# 3) Wait for pod and follow logs
echo "[STEP] Wait for test pod" | tee -a "${OUT_DIR}/job.log"
"$KUBECTL" -n "$NAMESPACE" wait --for=condition=Ready pod -l job-name=rag-integration-test --timeout=120s || true

POD=$("$KUBECTL" -n "$NAMESPACE" get pods -l job-name=rag-integration-test -o jsonpath='{.items[0].metadata.name}')
if [ -z "${POD}" ]; then
  echo "[ERROR] Could not find test pod" | tee -a "${OUT_DIR}/job.log"
  exit 1
fi

echo "[INFO] Test pod: ${POD}" | tee -a "${OUT_DIR}/job.log"
echo "[STEP] Stream job logs" | tee -a "${OUT_DIR}/job.log"
"$KUBECTL" -n "$NAMESPACE" logs -f "$POD" | tee "${OUT_DIR}/integration-tests.log"

# 4) Run Go E2E driver via Podman (optional)
echo "[STEP] Run Go E2E driver via Podman" | tee -a "${OUT_DIR}/go-e2e-driver.log"
if command -v podman >/dev/null 2>&1; then
  # Mount internal CA to podman container and set SSL_CERT_FILE
  # We assume combined-ca-inspect.crt in root is available as it was mentioned earlier.
  # Better: mount the same one we use elsewhere if available.
  podman run --rm \
    -v /mnt/hegemon-share/share/code/complete-build/rag-stack/tests:/app:Z \
    -v /mnt/hegemon-share/share/code/complete-build/combined-ca-inspect.crt:/etc/ssl/certs/internal-ca.crt:Z \
    -e SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    -w /app \
    golang:1.25-alpine \
    sh -c 'cat /etc/ssl/certs/internal-ca.crt >> /etc/ssl/certs/ca-certificates.crt && go run main.go' | tee -a "${OUT_DIR}/go-e2e-driver.log"
else
  echo "[WARN] podman not found; skipping Go E2E driver" | tee -a "${OUT_DIR}/go-e2e-driver.log"
fi

# 5) Summary
echo "[DONE] E2E run complete. Logs saved to ${OUT_DIR}"
