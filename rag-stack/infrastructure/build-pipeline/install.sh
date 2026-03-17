#!/bin/bash
# install.sh - Build Pipeline Infrastructure (S3 + Pulsar + Kaniko)
# To be executed on host: hierophant

set -Eeuo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
NAMESPACE="build-pipeline"
REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
ORCHESTRATOR_TAG="${ORCHESTRATOR_TAG:-latest}"

source "$REPO_DIR/../../../scripts/journal-helper.sh"
init_journal

should_run_step() {
    local step_name="$1"
    local verify_cmd="$2"
    if ! is_step_done "$step_name"; then
        return 0
    fi
    if ! eval "$verify_cmd" >/dev/null 2>&1; then
        echo "Journal has '$step_name' but live verification failed. Re-running step..."
        return 0
    fi
    return 1
}

if should_run_step "build-pipeline-ns" "$KUBECTL get namespace $NAMESPACE"; then
    echo "--- Creating Build Pipeline Namespace ---"
    # Extract the namespace from the manifest and apply it first
    $KUBECTL apply -f "$REPO_DIR/s3-build-storage.yaml" || {
        echo "Retrying namespace creation..."
        sleep 5
        $KUBECTL apply -f "$REPO_DIR/s3-build-storage.yaml"
    }
    mark_step_done "build-pipeline-ns"
fi

if should_run_step "build-pipeline-ca" "$KUBECTL get configmap -n $NAMESPACE registry-ca-cm"; then
    echo "--- Applying Registry CA ---"
    
    # Ensure SAFE_TMP_DIR exists
    mkdir -p "$SAFE_TMP_DIR"
    
    # Try to extract the CA from the in-cluster secret first, then fallback to Talos patch
    if $KUBECTL get secret in-cluster-registry-tls -n container-registry >/dev/null 2>&1; then
        echo "Extracting CA from container-registry/in-cluster-registry-tls..."
        $KUBECTL get secret in-cluster-registry-tls -n container-registry -o jsonpath='{.data.ca\.crt}' | base64 --decode > "$SAFE_TMP_DIR/ca.crt"
        $KUBECTL create configmap registry-ca-cm -n $NAMESPACE --from-file=ca.crt="$SAFE_TMP_DIR/ca.crt" --dry-run=client -o yaml | $KUBECTL apply -f -
    else
        # Fallback: Extract from talos patch if source secret is missing
        echo "Fallback: Extracting CA from Talos registry patch..."
        CA_B64=$(grep "ca: " "$REPO_DIR/../../../infrastructure/registry/talos-registry-patch.yaml" | head -n 1 | awk '{print $2}')
        if [ -n "$CA_B64" ]; then
            echo "$CA_B64" | base64 -d > "$SAFE_TMP_DIR/ca.crt"
            $KUBECTL create configmap registry-ca-cm -n $NAMESPACE --from-file=ca.crt="$SAFE_TMP_DIR/ca.crt" --dry-run=client -o yaml | $KUBECTL apply -f -
        else
            echo "WARNING: Could not find registry-ca-cm or Talos patch to inject CA."
        fi
    fi
    # Clean up the temporary cert file
    rm -f "$SAFE_TMP_DIR/ca.crt"
    mark_step_done "build-pipeline-ca"
fi

if should_run_step "build-orchestrator-image" "command -v skopeo >/dev/null 2>&1 && skopeo inspect --tls-verify=false docker://$REGISTRY/build-orchestrator:$ORCHESTRATOR_TAG"; then
    echo "--- Bootstrapping Build Orchestrator Image (Cluster-Native) ---"
    ORCHESTRATOR_TAG="$ORCHESTRATOR_TAG" REGISTRY="$REGISTRY" bash "$REPO_DIR/bootstrap-orchestrator.sh"
    mark_step_done "build-orchestrator-image"
fi

if should_run_step "build-orchestrator" "$KUBECTL rollout status deploy/build-orchestrator -n $NAMESPACE --timeout=30s"; then
    echo "--- Deploying Build Orchestrator ---"
    $KUBECTL apply -f "$REPO_DIR/orchestrator-deployment.yaml"
    $KUBECTL -n "$NAMESPACE" set image deploy/build-orchestrator orchestrator="$REGISTRY/build-orchestrator:$ORCHESTRATOR_TAG"
    # Force a fresh rollout in case the deployment is unchanged but prior pods are stuck.
    $KUBECTL rollout restart deploy/build-orchestrator -n $NAMESPACE || true
    if ! $KUBECTL rollout status deploy/build-orchestrator -n $NAMESPACE --timeout=300s; then
        echo "ERROR: build-orchestrator rollout failed; diagnostics follow."
        $KUBECTL -n "$NAMESPACE" get deploy,rs,pods -l app=build-orchestrator -o wide || true
        POD_NAME=$($KUBECTL -n "$NAMESPACE" get pods -l app=build-orchestrator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
        if [[ -n "$POD_NAME" ]]; then
            $KUBECTL -n "$NAMESPACE" describe pod "$POD_NAME" || true
        fi
        exit 1
    fi
    mark_step_done "build-orchestrator"
fi

echo "Build Pipeline Infrastructure Setup Complete."
