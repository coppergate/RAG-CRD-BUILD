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

  MODEL_BASE="$(echo "$MODEL" | cut -d: -f1)"
  MODEL_TAG="$(echo "$MODEL" | cut -s -d: -f2)"
  MODEL_TAG="${MODEL_TAG:-latest}"

  # Check if model is already present by looking for verified manifests and blobs.
  CHECK_MANIFEST="$(cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${SEEDER_NAME}-check
  namespace: ${NAMESPACE}
spec:
  nodeSelector:
    role: storage-node
  restartPolicy: Never
  containers:
    - name: check
      image: ${REGISTRY}/ollama/ollama:0.15.6
      command:
        - /bin/sh
        - -c
        - |
          set -eu
          MANIFEST_PATH="/ollama-models/models/manifests/${REGISTRY}/ollama/${MODEL_BASE}/${MODEL_TAG}"
          SHORT_MANIFEST_PATH="/ollama-models/models/manifests/registry.ollama.ai/library/${MODEL_BASE}/${MODEL_TAG}"
          BLOBS_DIR="/ollama-models/models/blobs"
          if [ -s "\$MANIFEST_PATH" ] && [ -s "\$SHORT_MANIFEST_PATH" ] && find "\$BLOBS_DIR" -type f 2>/dev/null | grep -q .; then
            echo READY
          else
            echo EMPTY
          fi
      volumeMounts:
        - name: models
          mountPath: /ollama-models
  volumes:
    - name: models
      persistentVolumeClaim:
        claimName: ${PVC_NAME}
EOF
)"

  $KUBECTL delete pod "${SEEDER_NAME}-check" -n "$NAMESPACE" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  printf '%s\n' "$CHECK_MANIFEST" | $KUBECTL apply -f - >/dev/null
  CHECK_OUTPUT="$(
    $KUBECTL wait --for=condition=Ready pod/"${SEEDER_NAME}-check" -n "$NAMESPACE" --timeout=30s >/dev/null 2>&1 || true
    $KUBECTL wait --for=jsonpath='{.status.phase}'=Succeeded pod/"${SEEDER_NAME}-check" -n "$NAMESPACE" --timeout=300s >/dev/null 2>&1 || true
    $KUBECTL logs "${SEEDER_NAME}-check" -n "$NAMESPACE" --tail=20 2>/dev/null || true
  )"
  EXISTING="$(printf '%s\n' "$CHECK_OUTPUT" | tail -n 1)"
  $KUBECTL delete pod "${SEEDER_NAME}-check" -n "$NAMESPACE" --ignore-not-found 2>/dev/null || true

  if [ -n "$EXISTING" ] && [ "$EXISTING" != "EMPTY" ]; then
    echo "  Model already present in PVC $PVC_NAME. Skipping."
    continue
  fi

  echo "  Pulling $MODEL from registry into PVC..."
  # Run a seeder pod whose init container mirrors the registry blobs into the PVC.
  SEEDER_MANIFEST="$(cat <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: __SEEDER_NAME__
  namespace: __NAMESPACE__
spec:
  nodeSelector:
    role: storage-node
  restartPolicy: Never
  initContainers:
    - name: seed-model
      image: curlimages/curl:7.78.0
      command:
        - /bin/sh
        - -c
        - |
          set -eu
          OLLAMA_MODELS=/ollama-models/models
          MODEL="__MODEL__"
          REGISTRY="__REGISTRY__"
          REPO="ollama/$(echo "$MODEL" | cut -d: -f1)"
          TAG="$(echo "$MODEL" | cut -s -d: -f2)"
          TAG="${TAG:-latest}"

          MANIFEST_DIR="$OLLAMA_MODELS/manifests/$REGISTRY/$REPO"
          MANIFEST_PATH="${MANIFEST_DIR}/${TAG}"
          SHORT_MANIFEST_DIR="$OLLAMA_MODELS/manifests/registry.ollama.ai/library/$(echo "$MODEL" | cut -d: -f1)"
          SHORT_MANIFEST_PATH="${SHORT_MANIFEST_DIR}/${TAG}"
          BLOBS_DIR="$OLLAMA_MODELS/blobs"

          mkdir -p "$MANIFEST_DIR" "$SHORT_MANIFEST_DIR" "$BLOBS_DIR"

          echo "Fetching manifest for ${REPO}:${TAG}..."
          curl -skL "https://$REGISTRY/v2/$REPO/manifests/$TAG" \
            -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
            -o "$MANIFEST_PATH"

          echo "Parsing layers..."
          LAYERS=$(grep -o 'sha256:[a-f0-9]*' "$MANIFEST_PATH" | sort -u)

          for LAYER in $LAYERS; do
            BLOB_FILE="${BLOBS_DIR}/${LAYER//:/-}"
            if [ -f "$BLOB_FILE" ] && [ -s "$BLOB_FILE" ]; then
              echo "  Blob $LAYER already exists. Skipping."
              continue
            fi
            echo "  Downloading blob $LAYER..."
            curl -skL "https://$REGISTRY/v2/$REPO/blobs/$LAYER" -o "$BLOB_FILE"
          done

          echo "Creating short-name manifest..."
          cp "$MANIFEST_PATH" "$SHORT_MANIFEST_PATH"
          echo "Verifying seeded files..."
          test -s "$MANIFEST_PATH"
          test -s "$SHORT_MANIFEST_PATH"
          find "$BLOBS_DIR" -type f | grep -q .
          echo "SUCCESS: Manual seeding complete for __MODEL__"
      securityContext:
        runAsUser: 0
        runAsGroup: 0
        allowPrivilegeEscalation: false
      volumeMounts:
        - name: models
          mountPath: /ollama-models
        - name: registry-ca
          mountPath: /etc/ssl/certs/ca-certificates.crt
          subPath: ca.crt
  containers:
    - name: complete
      image: busybox:1.37.0
      command:
        - /bin/sh
        - -c
        - "echo 'Seed pod complete.'"
      env:
        - name: SSL_CERT_FILE
          value: "/etc/ssl/certs/ca-certificates.crt"
        - name: OLLAMA_MODELS
          value: "/ollama-models/models"
        - name: REGISTRY
          value: "__REGISTRY__"
      volumeMounts:
        - name: models
          mountPath: /ollama-models
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
        claimName: __PVC_NAME__
    - name: registry-ca
      configMap:
        name: registry-ca-cm
EOF
)"

  SEEDER_MANIFEST="${SEEDER_MANIFEST//__SEEDER_NAME__/$SEEDER_NAME}"
  SEEDER_MANIFEST="${SEEDER_MANIFEST//__NAMESPACE__/$NAMESPACE}"
  SEEDER_MANIFEST="${SEEDER_MANIFEST//__REGISTRY__/$REGISTRY}"
  SEEDER_MANIFEST="${SEEDER_MANIFEST//__PVC_NAME__/$PVC_NAME}"
  SEEDER_MANIFEST="${SEEDER_MANIFEST//__MODEL__/$MODEL}"

  $KUBECTL delete pod "$SEEDER_NAME" -n "$NAMESPACE" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  printf '%s\n' "$SEEDER_MANIFEST" | $KUBECTL apply -f -

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
    exit 1
  fi

  # Cleanup seeder pod
  $KUBECTL delete pod "$SEEDER_NAME" -n "$NAMESPACE" --ignore-not-found 2>/dev/null
done

echo ""
echo "=== Model Seeding Complete ==="
