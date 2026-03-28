#!/bin/bash
# seed-models.sh — Seed LLM models from local registry into Ollama PVCs
# Run AFTER ollama PVCs exist but BEFORE starting ollama deployments with models.
# Models must have been pre-pushed to the local registry via pre-pull-models.sh.
#
# To be executed on host: hierophant
set -euo pipefail

KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
NAMESPACE="llms-ollama"
REGISTRY="registry.container-registry.svc.cluster.local:5000"

# Model-to-PVC mapping (model_name:pvc_name)
declare -A MODEL_PVC_MAP=(
  ["llama3.1"]="ollama-llama3"
  ["granite3.1-dense:8b"]="ollama-granite31-8b"
)

echo "=== Ollama Model Seeding ==="
echo "Namespace: $NAMESPACE"
echo "Registry:  $REGISTRY"
echo ""

for MODEL in "${!MODEL_PVC_MAP[@]}"; do
  PVC_NAME="${MODEL_PVC_MAP[$MODEL]}"
  SEEDER_NAME="model-seeder-$(echo "$PVC_NAME" | tr '.' '-')"

  echo "--- Seeding $MODEL into PVC $PVC_NAME ---"

  # Check if PVC exists
  if ! $KUBECTL get pvc "$PVC_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "  WARNING: PVC $PVC_NAME does not exist yet. Skipping $MODEL."
    continue
  fi

  # Check if model is already present by looking for manifests
  EXISTING=$($KUBECTL run "$SEEDER_NAME-check" \
    --image="${REGISTRY}/ollama/ollama:0.15.6" \
    --restart=Never \
    --rm -i --quiet \
    -n "$NAMESPACE" \
    --overrides="{
      \"spec\": {
        \"nodeSelector\": {\"node-role.kubernetes.io/storage-node\": \"\"},
        \"containers\": [{
          \"name\": \"check\",
          \"image\": \"${REGISTRY}/ollama/ollama:0.15.6\",
          \"command\": [\"sh\", \"-c\", \"find /root/.ollama/models/manifests -type f 2>/dev/null | head -1 || echo EMPTY\"],
          \"volumeMounts\": [{\"name\": \"models\", \"mountPath\": \"/root/.ollama/models\"}]
        }],
        \"volumes\": [{\"name\": \"models\", \"persistentVolumeClaim\": {\"claimName\": \"$PVC_NAME\"}}]
      }
    }" 2>/dev/null || echo "EMPTY")

  if [ -n "$EXISTING" ] && [ "$EXISTING" != "EMPTY" ]; then
    echo "  Model already present in PVC $PVC_NAME. Skipping."
    continue
  fi

  echo "  Pulling $MODEL from registry into PVC..."
  # Run a seeder pod that starts ollama, pulls the model from local registry, then exits
  cat <<EOF | $KUBECTL apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $SEEDER_NAME
  namespace: $NAMESPACE
spec:
  nodeSelector:
    role: storage-node
  restartPolicy: Never
  containers:
    - name: seeder
      image: ${REGISTRY}/ollama/ollama:0.15.6
      command:
        - /bin/sh
        - -c
        - |
          echo "Starting Ollama for model seeding..."
          OLLAMA_MODELS=/root/.ollama/models ollama serve &
          OLLAMA_PID=\$!
          # Wait for ollama to be ready (max 60s)
          for i in \$(seq 1 60); do
            if ollama list >/dev/null 2>&1; then
              echo "Ollama ready after \${i}s"
              break
            fi
            if [ "\$i" -eq 60 ]; then
              echo "ERROR: Ollama did not start"
              kill \$OLLAMA_PID 2>/dev/null
              exit 1
            fi
            sleep 1
          done
          echo "Pulling ${REGISTRY}/ollama/${MODEL}..."
          if ollama pull "${REGISTRY}/ollama/${MODEL}"; then
            echo "SUCCESS: ${MODEL} seeded from local registry"
            # Tag it as the short name so Ollama pods can find it easily
            ollama cp "${REGISTRY}/ollama/${MODEL}" "${MODEL}"
          else
            echo "ERROR: Failed to pull ${MODEL} from local registry"
            kill \$OLLAMA_PID 2>/dev/null
            exit 1
          fi
          kill \$OLLAMA_PID 2>/dev/null
          echo "Seeding complete."
      env:
        - name: SSL_CERT_FILE
          value: "/etc/ssl/certs/ca-certificates.crt"
      volumeMounts:
        - name: models
          mountPath: /root/.ollama/models
        - name: registry-ca
          mountPath: /etc/ssl/certs/ca-certificates.crt
          subPath: ca.crt
      resources:
        requests:
          memory: "512Mi"
          cpu: "500m"
        limits:
          memory: "2Gi"
          cpu: "2"
  volumes:
    - name: models
      persistentVolumeClaim:
        claimName: $PVC_NAME
    - name: registry-ca
      configMap:
        name: registry-ca-cm
EOF

  echo "  Waiting for seeder pod $SEEDER_NAME to complete (timeout 1800s)..."
  if $KUBECTL wait --for=condition=Ready pod/"$SEEDER_NAME" -n "$NAMESPACE" --timeout=30s 2>/dev/null; then
    true  # pod is running
  fi
  $KUBECTL wait --for=jsonpath='{.status.phase}'=Succeeded pod/"$SEEDER_NAME" -n "$NAMESPACE" --timeout=1800s 2>/dev/null || true
  PHASE=$($KUBECTL get pod "$SEEDER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)

  if [ "$PHASE" = "Succeeded" ]; then
    echo "  ✓ $MODEL seeded into $PVC_NAME"
  else
    echo "  ✗ Seeding failed for $MODEL. Pod logs:"
    $KUBECTL logs "$SEEDER_NAME" -n "$NAMESPACE" --tail=20 2>/dev/null || true
  fi

  # Cleanup seeder pod
  $KUBECTL delete pod "$SEEDER_NAME" -n "$NAMESPACE" --ignore-not-found 2>/dev/null
done

echo ""
echo "=== Model Seeding Complete ==="
