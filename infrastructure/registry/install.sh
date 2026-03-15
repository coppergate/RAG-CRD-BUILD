#!/bin/bash
# install.sh - Local Registry Installation
# To be executed on host: hierophant

set -e

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
BOOTSTRAP_REGISTRY="${BOOTSTRAP_REGISTRY:-10.0.0.1:5000}"
BOOTSTRAP_IMAGE="${BOOTSTRAP_IMAGE:-registry:2}"

source "${BASE_DIR:-.}/scripts/journal-helper.sh"
init_journal

seed_registry_image_into_bootstrap_registry() {
  local target="${BOOTSTRAP_REGISTRY}/${BOOTSTRAP_IMAGE}"
  echo "--- 0. Ensuring bootstrap image exists: ${target} ---"

  if command -v skopeo >/dev/null 2>&1; then
    if skopeo inspect --tls-verify=true "docker://${target}" >/dev/null 2>&1; then
      echo "Bootstrap image already present: ${target}"
      return 0
    fi
    skopeo copy --all --src-tls-verify=true --dest-tls-verify=true \
      "docker://${BOOTSTRAP_IMAGE}" "docker://${target}"
    return 0
  fi

  if command -v podman >/dev/null 2>&1; then
    if podman manifest inspect "docker://${target}" >/dev/null 2>&1; then
      echo "Bootstrap image already present: ${target}"
      return 0
    fi
    podman pull "docker.io/library/${BOOTSTRAP_IMAGE}"
    podman tag "docker.io/library/${BOOTSTRAP_IMAGE}" "${target}"
    podman push --tls-verify=true "${target}"
    return 0
  fi

  echo "ERROR: neither skopeo nor podman found; cannot seed ${target}" >&2
  return 1
}

if ! is_step_done "registry-namespace"; then
$KUBECTL get namespace container-registry >/dev/null 2>&1 || $KUBECTL create namespace container-registry
$KUBECTL get namespace cert-manager >/dev/null 2>&1 || $KUBECTL create namespace cert-manager
mark_step_done "registry-namespace"
fi

if ! is_step_done "registry-tls"; then
echo "--- 0.1 Applying Registry TLS (Cert-Manager) ---"
$KUBECTL apply -f "$REPO_DIR/cert-manager-tls.yaml"
# wait for the certificate to be ready
$KUBECTL wait --for=condition=Ready certificate/in-cluster-registry-cert -n container-registry --timeout=120s
mark_step_done "registry-tls"
fi

if ! is_step_done "registry-deploy"; then
echo "--- 1. Deploying Local Registry to K8s ---"
$KUBECTL apply -f "$REPO_DIR/registry.yaml"
mark_step_done "registry-deploy"
fi

if ! is_step_done "registry-wait"; then
echo "--- 1.1 Waiting for Registry Pod to be Ready ---"
$KUBECTL wait --for=condition=ready pod -l app=registry -n container-registry --timeout=120s
mark_step_done "registry-wait"
fi

if ! is_step_done "registry-seed-image"; then
echo "--- 1.2 Seeding bootstrap registry image ---"
seed_registry_image_into_bootstrap_registry
mark_step_done "registry-seed-image"
fi

if ! is_step_done "registry-patch"; then
echo "--- 2. Applying Talos Registry Patches ---"
# Note: apply-patch.sh expects absolute paths and uses talosctl
bash "$REPO_DIR/apply-patch.sh"
mark_step_done "registry-patch"
fi

clear_journal

echo "Local Registry Setup Complete."
