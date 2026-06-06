#!/bin/bash
set -euo pipefail

KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"
REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rag-stack"

declare -A VERSIONS=(
    [db-adapter]="2.4.18"
    [llm-gateway]="2.4.19"
    [prompt-aggregator]="2.4.15"
    [qdrant-adapter]="2.4.20"
    [rag-worker]="2.4.44"
)

for svc in "${!VERSIONS[@]}"; do
    ver="${VERSIONS[$svc]}"
    manifest="$REPO_DIR/services/$svc/k8s/deployment.yaml"
    echo "Deploying $svc @ $ver ..."
    sed -e "s#__VERSION__#${ver}#g" \
        -e "s#registry.hierocracy.home:5000#${REGISTRY}#g" \
        -e "s#registry.container-registry.svc.cluster.local:5000#${REGISTRY}#g" \
        "$manifest" | "$KUBECTL" apply -f -
done

echo "Done."