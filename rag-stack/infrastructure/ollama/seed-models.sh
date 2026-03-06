#!/bin/bash
# seed-models.sh - Pre-populate Ollama PVCs with models
# Run on hierophant

KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
NAMESPACE="llms-ollama"
REGISTRY="registry.hierocracy.home:5000"

echo "--- Seeding Models into PVCs ---"

# 1. Scaling down to avoid locks
echo "[STEP 1] Scaling down Ollama deployments..."
$KUBECTL -n $NAMESPACE scale deployment ollama-llama3 --replicas=0
$KUBECTL -n $NAMESPACE scale deployment ollama-granite31-8b --replicas=0

# 2. Start a seeder pod that mounts both PVCs
echo "[STEP 2] Launching seeder pod..."
cat <<EOF | $KUBECTL apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ollama-seeder
  namespace: $NAMESPACE
spec:
  containers:
  - name: seeder
    image: $REGISTRY/ollama/ollama:0.15.6
    command: ["sleep", "3600"]
    volumeMounts:
    - name: llama3-data
      mountPath: /mnt/llama3
    - name: granite-data
      mountPath: /mnt/granite
  volumes:
  - name: llama3-data
    persistentVolumeClaim:
      claimName: ollama-llama3
  - name: granite-data
    persistentVolumeClaim:
      claimName: ollama-granite31-8b
EOF

echo "Waiting for seeder pod to be ready..."
$KUBECTL -n $NAMESPACE wait --for=condition=Ready pod/ollama-seeder --timeout=60s

# 3. Pull models into the mounted directories
# Ollama stores models in .ollama/models
echo "[STEP 3] Pulling models into PVCs..."

# Seed Llama 3.1
echo "Seeding llama3.1..."
$KUBECTL -n $NAMESPACE exec ollama-seeder -- sh -c "OLLAMA_MODELS=/mnt/llama3/models ollama serve & sleep 5 && ollama pull llama3.1 && pkill ollama"

# Seed Granite
echo "Seeding granite3.1-dense:8b..."
$KUBECTL -n $NAMESPACE exec ollama-seeder -- sh -c "OLLAMA_MODELS=/mnt/granite/models ollama serve & sleep 5 && ollama pull granite3.1-dense:8b && pkill ollama"

# 4. Cleanup
echo "[STEP 4] Cleaning up seeder pod..."
$KUBECTL -n $NAMESPACE delete pod ollama-seeder

echo "[DONE] Models seeded. You can now scale up Ollama deployments with model pulling disabled."
