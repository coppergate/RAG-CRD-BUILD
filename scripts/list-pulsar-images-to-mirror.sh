#!/bin/bash
# list-pulsar-images-to-mirror.sh
# Collect unique images used by Pulsar pods and print mirror commands.

set -Eeuo pipefail

KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"
NS="${PULSAR_NAMESPACE:-apache-pulsar}"
TARGET_REGISTRY="${TARGET_REGISTRY:-registry.hierocracy.home:5000}"

if ! "$KUBECTL" --request-timeout=10s get ns "$NS" >/dev/null 2>&1; then
  echo "ERROR: Namespace '$NS' not reachable. Check cluster access/KUBECONFIG." >&2
  exit 1
fi

if ! "$KUBECTL" get pods -n "$NS" >/dev/null 2>&1; then
  echo "ERROR: Could not list pods in namespace '$NS'." >&2
  exit 1
fi

images="$($KUBECTL get pods -n "$NS" -o jsonpath='{range .items[*]}{range .spec.initContainers[*]}{.image}{"\n"}{end}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sed '/^$/d' | sort -u)"

if [[ -z "$images" ]]; then
  echo "No images found in namespace '$NS'."
  exit 0
fi

echo "Unique images in $NS:"
echo "----------------------------------------"
echo "$images"
echo

echo "Suggested mirror commands (skopeo):"
echo "----------------------------------------"
while IFS= read -r img; do
  [[ -z "$img" ]] && continue
  # Keep source path exactly; only prepend target registry
  dest="$TARGET_REGISTRY/$img"
  echo "skopeo copy docker://$img docker://$dest"
done <<< "$images"

echo
echo "Tip: run with parallelism (after review):"
echo "  TARGET_REGISTRY=$TARGET_REGISTRY bash $0 | grep '^skopeo copy' | xargs -n1 -P4 -I{} bash -lc '{}'"
