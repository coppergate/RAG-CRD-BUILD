#!/bin/bash
# install.sh - Grafana LGTM Stack (Loki, Grafana, Tempo, Mimir)
# To be executed on host: hierophant

set -Eeuo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
NAMESPACE="monitoring"

source "$REPO_DIR/../../scripts/journal-helper.sh"
init_journal

OBC_WAIT_TIMEOUT_SECONDS="${OBC_WAIT_TIMEOUT_SECONDS:-600}"
OBC_WAIT_POLL_SECONDS="${OBC_WAIT_POLL_SECONDS:-5}"

function obc_diagnostics() {
    local bucket="$1"
    echo "Diagnostics for $bucket:"
    $KUBECTL get obc "$bucket" -n "$NAMESPACE" -o wide || true
    $KUBECTL get obc "$bucket" -n "$NAMESPACE" -o yaml | sed -n '1,220p' || true
    $KUBECTL get storageclass rook-ceph-bucket -o wide || true
    $KUBECTL get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -n 40 || true
}

function wait_for_bucket_secret() {
    local bucket="$1"
    local waited=0

    echo "Checking bucket: $bucket"
    while ! $KUBECTL get secret "$bucket" -n "$NAMESPACE" >/dev/null 2>&1; do
        local phase=""
        phase="$($KUBECTL get obc "$bucket" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
        echo "Still waiting for $bucket... phase=${phase:-unknown} elapsed=${waited}s"
        sleep "$OBC_WAIT_POLL_SECONDS"
        waited=$((waited + OBC_WAIT_POLL_SECONDS))
        if [[ "$waited" -ge "$OBC_WAIT_TIMEOUT_SECONDS" ]]; then
            echo "ERROR: Timeout waiting for bucket secret for $bucket after ${OBC_WAIT_TIMEOUT_SECONDS}s"
            obc_diagnostics "$bucket"
            return 1
        fi
    done

    echo "Bucket $bucket is ready."
}

if ! is_step_done "monitoring-ns"; then
    echo "--- Creating Monitoring Namespace ---"
    $KUBECTL create namespace $NAMESPACE || true
    $KUBECTL label --overwrite namespace $NAMESPACE \
      pod-security.kubernetes.io/audit=privileged \
      pod-security.kubernetes.io/warn=privileged \
      pod-security.kubernetes.io/enforce=privileged
    mark_step_done "monitoring-ns"
else
    echo "--- Step 'monitoring-ns' already completed, skipping ---"
fi

if ! is_step_done "registry-ca-cm"; then
    echo "--- Creating Registry CA ConfigMap in $NAMESPACE ---"
    # Ensure SAFE_TMP_DIR exists (it's initialized in journal-helper.sh)
    mkdir -p "$SAFE_TMP_DIR"
    
    # Try to copy the CA from the container-registry secret if available
    if $KUBECTL get secret in-cluster-registry-tls -n container-registry >/dev/null 2>&1; then
        echo "Copying CA from container-registry/in-cluster-registry-tls..."
        $KUBECTL get secret in-cluster-registry-tls -n container-registry -o jsonpath='{.data.ca\.crt}' | base64 --decode > "$SAFE_TMP_DIR/ca.crt"
        $KUBECTL create configmap registry-ca-cm -n $NAMESPACE --from-file=ca.crt="$SAFE_TMP_DIR/ca.crt" --dry-run=client -o yaml | $KUBECTL apply -f -
    else
        echo "WARNING: in-cluster-registry-tls secret not found. Using fallback CA from talos-registry-patch.yaml..."
        # Fallback extraction from the patch file if the secret isn't there yet
        grep "ca:" "$REPO_DIR/../registry/talos-registry-patch.yaml" | head -n 1 | awk '{print $2}' | base64 --decode > "$SAFE_TMP_DIR/ca.crt"
        $KUBECTL create configmap registry-ca-cm -n $NAMESPACE --from-file=ca.crt="$SAFE_TMP_DIR/ca.crt" --dry-run=client -o yaml | $KUBECTL apply -f -
    fi
    mark_step_done "registry-ca-cm"
else
    echo "--- Step 'registry-ca-cm' already completed, skipping ---"
fi

if ! is_step_done "s3-obc"; then
    echo "--- Provisioning S3 Buckets for APM ---"
    $KUBECTL apply -f "$REPO_DIR/common/s3-storage.yaml"
    
    # Wait for OBCs to be bound
    echo "Waiting for buckets to be ready (timeout=${OBC_WAIT_TIMEOUT_SECONDS}s)..."
    for bucket in loki-s3-bucket tempo-s3-bucket mimir-s3-bucket mimir-ruler-s3-bucket mimir-alertmanager-s3-bucket; do
        wait_for_bucket_secret "$bucket"
    done
    mark_step_done "s3-obc"
else
    echo "--- Step 's3-obc' already completed, skipping ---"
fi

function deploy_lgtm_component() {
    local name=$1
    local chart=$2
    local repo_url=$3
    local bucket_secret=$4
    
    if ! is_step_done "deploy-$name"; then
        echo "--- Deploying $name ---"
        
        # Cleanup potential leftovers from previous failed attempts
        if [[ "$name" == "tempo" ]]; then
            echo "Checking for legacy tempo resources..."
            $KUBECTL delete statefulset tempo -n $NAMESPACE --ignore-not-found
            $KUBECTL delete svc tempo -n $NAMESPACE --ignore-not-found
            # Also clean up any other resources with the old name to avoid conflicts with tempo-distributed
            $KUBECTL delete all -n $NAMESPACE -l app.kubernetes.io/instance=tempo --ignore-not-found
        fi

        # Extract S3 credentials
        echo "Extracting S3 credentials for $name from secret $bucket_secret..."
        S3_ENDPOINT=$($KUBECTL get configmap $bucket_secret -n $NAMESPACE -o jsonpath='{.data.BUCKET_HOST}')
        BUCKET_NAME=$($KUBECTL get configmap $bucket_secret -n $NAMESPACE -o jsonpath='{.data.BUCKET_NAME}')
        AWS_ACCESS_KEY_ID=$($KUBECTL get secret $bucket_secret -n $NAMESPACE -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 --decode)
        AWS_SECRET_ACCESS_KEY=$($KUBECTL get secret $bucket_secret -n $NAMESPACE -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 --decode)
        
        echo "Generating values.yaml for $name in $SAFE_TMP_DIR..."
        # Create temporary values file from template
        export S3_ENDPOINT BUCKET_NAME AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
        
        # Additional bucket extraction for Mimir dedicated storage
        if [[ "$name" == "mimir" ]]; then
            RULER_BUCKET_NAME=$($KUBECTL get configmap mimir-ruler-s3-bucket -n $NAMESPACE -o jsonpath='{.data.BUCKET_NAME}')
            ALERTMANAGER_BUCKET_NAME=$($KUBECTL get configmap mimir-alertmanager-s3-bucket -n $NAMESPACE -o jsonpath='{.data.BUCKET_NAME}')
            
            RULER_ACCESS_KEY=$($KUBECTL get secret mimir-ruler-s3-bucket -n $NAMESPACE -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 --decode)
            RULER_SECRET_KEY=$($KUBECTL get secret mimir-ruler-s3-bucket -n $NAMESPACE -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 --decode)
            
            ALERTMANAGER_ACCESS_KEY=$($KUBECTL get secret mimir-alertmanager-s3-bucket -n $NAMESPACE -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 --decode)
            ALERTMANAGER_SECRET_KEY=$($KUBECTL get secret mimir-alertmanager-s3-bucket -n $NAMESPACE -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 --decode)
            
            export RULER_BUCKET_NAME ALERTMANAGER_BUCKET_NAME RULER_ACCESS_KEY RULER_SECRET_KEY ALERTMANAGER_ACCESS_KEY ALERTMANAGER_SECRET_KEY
        fi
        
        envsubst < "$REPO_DIR/$name/values.yaml.template" > "$SAFE_TMP_DIR/$name-values.yaml"
        
        echo "Adding Helm repo $repo_url..."
        helm repo add grafana $repo_url
        helm repo update
        
        echo "Executing helm upgrade for $name (this may take several minutes)..."
        echo "Chart: $chart"
        helm upgrade --install $name $chart \
            --namespace $NAMESPACE \
            --values "$SAFE_TMP_DIR/$name-values.yaml" \
            --wait --timeout 15m \
            --debug
        
        mark_step_done "deploy-$name"
    else
        echo "--- Step 'deploy-$name' already completed, skipping ---"
    fi
}

deploy_lgtm_component "loki" "grafana/loki" "https://grafana.github.io/helm-charts" "loki-s3-bucket"
deploy_lgtm_component "tempo" "grafana/tempo" "https://grafana.github.io/helm-charts" "tempo-s3-bucket"
deploy_lgtm_component "mimir" "grafana/mimir-distributed" "https://grafana.github.io/helm-charts" "mimir-s3-bucket"

if ! is_step_done "deploy-otel-collector"; then
    echo "--- Deploying OpenTelemetry Collector ---"
    $KUBECTL apply -f "$REPO_DIR/otel-collector/otel-collector.yaml"
    mark_step_done "deploy-otel-collector"
fi

if ! is_step_done "deploy-grafana"; then
    echo "--- Deploying Grafana Operator and Instance ---"
    
    echo "Adding Grafana Operator repo..."
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    echo "Installing Grafana Operator..."
    helm upgrade --install grafana-operator grafana/grafana-operator \
        --namespace $NAMESPACE \
        --set nodeSelector.role=storage-node \
        --wait
    
    echo "Applying Grafana Operator manifests..."
    $KUBECTL apply -f "$REPO_DIR/grafana/operator-manifests.yaml"
    
    mark_step_done "deploy-grafana"
fi

if ! is_step_done "deploy-alloy"; then
    echo "--- Deploying Grafana Alloy (Metric Scraper) ---"
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    helm upgrade --install alloy grafana/alloy \
        --namespace $NAMESPACE \
        --values "$REPO_DIR/alloy/values.yaml" \
        --wait
    mark_step_done "deploy-alloy"
fi

clear_journal
echo "Grafana LGTM Stack Installation Complete."
