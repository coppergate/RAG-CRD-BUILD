#!/usr/bin/env bash
set -Eeuo pipefail

cd /mnt/hegemon-share/share/code/complete-build

export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"
K="${K:-/home/k8s/kube/kubectl}"

BOOTSTRAP_REGISTRY="${BOOTSTRAP_REGISTRY:-registry.hierocracy.home:5000}"
CLUSTER_REGISTRY="${CLUSTER_REGISTRY:-registry.container-registry.svc.cluster.local:5000}"

# Source of truth for versioning
if [[ -z "${VERSION:-}" ]]; then
    if [[ -f "CURRENT_VERSION" ]]; then
        VERSION=$(cat "CURRENT_VERSION" | tr -d '[:space:]')
    else
        VERSION="2.4.9"
    fi
fi
export VERSION

PARALLELISM="${PARALLELISM:-4}"

echo "=== 1) Mirror missing OLM digest to bootstrap registry ==="
OLM_DIGEST="sha256:e74b2ac57963c7f3ba19122a8c31c9f2a0deb3c0c5cac9e5323ccffd0ca198ed"
SRC_REF="quay.io/operator-framework/olm@${OLM_DIGEST}"
DST_TAG_REF="${BOOTSTRAP_REGISTRY}/quay.io/operator-framework/olm:olm-e74b2ac5"
DST_DIGEST_REF="${BOOTSTRAP_REGISTRY}/quay.io/operator-framework/olm@${OLM_DIGEST}"

skopeo copy --all \
  --src-tls-verify=true \
  --dest-tls-verify=false \
  "docker://${SRC_REF}" \
  "docker://${DST_TAG_REF}"

skopeo inspect --tls-verify=false "docker://${DST_TAG_REF}" >/dev/null
skopeo inspect --tls-verify=false "docker://${DST_DIGEST_REF}" >/dev/null
echo "OK mirrored ${DST_TAG_REF} and verified ${DST_DIGEST_REF}"

echo "=== 2) Mirror bootstrap/install images to bootstrap registry ==="
APPLY=true \
TARGET_REGISTRY="${BOOTSTRAP_REGISTRY}" \
MIRROR_GROUPS=bootstrap,storage,apm-core,pulsar-core,registry,data-services,ollama \
PARALLELISM="${PARALLELISM}" \
bash scripts/mirror-all-images.sh

echo "=== 3) Build all service images to in-cluster registry ==="
REGISTRY="${CLUSTER_REGISTRY}" \
bash rag-stack/build.sh --mode cluster --wait

echo "=== 4) Verify built service images in in-cluster registry ==="
services=(
  llm-gateway
  rag-worker
  rag-web-ui
  rag-ingestion
  db-adapter
  qdrant-adapter
  object-store-mgr
  build-orchestrator
  rag-test-runner
)

for s in "${services[@]}"; do
  for t in "${VERSION}" latest; do
    if skopeo inspect --tls-verify=false "docker://${CLUSTER_REGISTRY}/${s}:${t}" >/dev/null 2>&1; then
      echo "OK ${CLUSTER_REGISTRY}/${s}:${t}"
    else
      echo "MISSING ${CLUSTER_REGISTRY}/${s}:${t}"
    fi
  done
done

echo "=== 5) Deploy stack from built images ==="
VERSION="${VERSION}" \
bash rag-stack/setup-all.sh

echo "=== Done ==="
