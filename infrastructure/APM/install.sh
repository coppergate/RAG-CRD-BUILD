#!/bin/bash
# install.sh - Grafana LGTM Stack (Loki, Grafana, Tempo, Mimir)
# To be executed on host: hierophant

set -e

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
NAMESPACE="monitoring"

source "$REPO_DIR/../../scripts/journal-helper.sh"
init_journal

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

if ! is_step_done "s3-obc"; then
    echo "--- Provisioning S3 Buckets for APM ---"
    $KUBECTL apply -f "$REPO_DIR/common/s3-storage.yaml"
    
    # Wait for OBCs to be bound
    echo "Waiting for buckets to be ready..."
    for bucket in loki-s3-bucket tempo-s3-bucket mimir-s3-bucket mimir-ruler-s3-bucket mimir-alertmanager-s3-bucket; do
        echo "Checking bucket: $bucket"
        until $KUBECTL get secret $bucket -n $NAMESPACE >/dev/null 2>&1; do
            echo "Still waiting for $bucket..."
            sleep 5
        done
        echo "Bucket $bucket is ready."
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
        
        echo "Generating values.yaml for $name in /tmp..."
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
        
        envsubst < "$REPO_DIR/$name/values.yaml.template" > "/tmp/$name-values.yaml"
        
        echo "Adding Helm repo $repo_url..."
        helm repo add grafana $repo_url
        helm repo update
        
        echo "Executing helm upgrade for $name (this may take several minutes)..."
        echo "Chart: $chart"
        helm upgrade --install $name $chart \
            --namespace $NAMESPACE \
            --values "/tmp/$name-values.yaml" \
            --wait --timeout 15m \
            --debug
        
        mark_step_done "deploy-$name"
    else
        echo "--- Step 'deploy-$name' already completed, skipping ---"
    fi
}

deploy_lgtm_component "loki" "grafana/loki" "https://grafana.github.io/helm-charts" "loki-s3-bucket"
deploy_lgtm_component "tempo" "grafana/tempo-distributed" "https://grafana.github.io/helm-charts" "tempo-s3-bucket"
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
