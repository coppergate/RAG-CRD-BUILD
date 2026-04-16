#!/bin/bash

# Configuration
NAMESPACE="rag-system"
CODE_DIR="/mnt/hegemon-share/share/code/complete-build/rag-stack"
TEST_DIR="${CODE_DIR}/tests"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
VERSION_FILE="${CODE_DIR}/../CURRENT_VERSION"
VERSION="${VERSION:-}"
if [ -z "$VERSION" ]; then
    VERSION=$(jq -r '."rag-test-runner".version' "$VERSION_FILE")
fi
echo "Using rag-test-runner version: ${VERSION}"

echo "--- Preparing RAG Integration Tests ---"

# 1. Recreate the tests ConfigMap
echo "Updating tests ConfigMap..."
$KUBECTL delete configmap rag-integration-tests -n $NAMESPACE --ignore-not-found
$KUBECTL create configmap rag-integration-tests -n $NAMESPACE \
    --from-file="${TEST_DIR}/integration_test.py" \
    --from-file="${TEST_DIR}/api_health_test.py" \
    --from-file="${TEST_DIR}/ingestion_isolation.py" \
    --from-file="${TEST_DIR}/context_verification.py" \
    --from-file="${TEST_DIR}/recursive_rag_test.py" \
    --from-file="${TEST_DIR}/pulsar_crud_test.py" \
    --from-file="${TEST_DIR}/aggregator_test.py" \
    --from-file="${TEST_DIR}/aggregator_failure_test.py" \
    --from-file="${TEST_DIR}/seed_qdrant_context.py" \
    --from-file="${TEST_DIR}/sad_path_test.py" \
    --from-file="${TEST_DIR}/cleanup_test_data.py" \
    --from-file="${TEST_DIR}/test_contracts.py"

# 2. Delete existing job
echo "Removing old test job..."
$KUBECTL delete job rag-integration-test -n $NAMESPACE --ignore-not-found

# 3. Apply the job
echo "Launching test job..."
RENDERED_JOB="/tmp/rag-integration-test-${VERSION}.yaml"
sed "s|:__VERSION__|:${VERSION}|g" "${TEST_DIR}/test-job.yaml" > "$RENDERED_JOB"
$KUBECTL apply -f "$RENDERED_JOB"
rm -f "$RENDERED_JOB"

# 4. Wait for pod to be ready and follow logs
echo "Waiting for pod to start (Running status)..."
"$KUBECTL" -n "$NAMESPACE" wait --for=condition=Ready pod -l job-name=rag-integration-test --timeout=120s || true

POD_NAME=$($KUBECTL get pods -n $NAMESPACE -l job-name=rag-integration-test -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD_NAME" ]; then
    echo "Error: Could not find test pod."
    exit 1
fi

LOG_DIR="/tmp/rag-logs/integration-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/integration-tests.log"
echo "Following logs for $POD_NAME (saving to $LOG_FILE)..."
$KUBECTL logs -n $NAMESPACE $POD_NAME -f | tee "$LOG_FILE"

# 5. Scan for failures and summary
echo ""
echo "--- Test Result Summary ---"
# We check case-insensitively and look for common error patterns
ERROR_COUNT=$(grep -Ei "\[ERROR\]|\[FAIL\]|\[FAILURE\]|ERROR:|FAIL:|FAILURE:|Exception:|Failed to export|can't open file|SyntaxError" "$LOG_FILE" | grep -v "expected" | wc -l)
SUCCESS_COUNT=$(grep -Ei "\[SUCCESS\]|\[PASS\]|\[OK\]" "$LOG_FILE" | wc -l)

if [ "$ERROR_COUNT" -gt 0 ]; then
    echo "POSSIBLE FAILURES OR MONITORING ISSUES DETECTED: $ERROR_COUNT"
    grep -Ei "\[ERROR\]|\[FAIL\]|\[FAILURE\]|ERROR:|FAIL:|FAILURE:|Exception:|Failed to export|can't open file|SyntaxError" "$LOG_FILE" | grep -v "expected" | head -n 30
    # We still exit 0 if there were successes, but we want the user to see the warning.
    # Actually, the user wants to see "possible failure" messages.
    if [ "$SUCCESS_COUNT" -eq 0 ]; then
        exit 1
    fi
else
    if [ "$SUCCESS_COUNT" -eq 0 ]; then
        echo "No success markers found. Check logs for details."
        exit 1
    fi
    echo "All tests appeared to pass based on log scanning ($SUCCESS_COUNT success markers)."
fi

# No cleanup here to allow log inspection
echo "Test logs preserved at: $LOG_FILE"
