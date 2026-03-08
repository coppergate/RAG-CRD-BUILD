#!/bin/bash
# Prefetch container images to node-local caches via a temporary DaemonSet.
# Intended for pre-registry bootstrap scenarios (e.g., Rook-Ceph chicken/egg).

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLAN_FILE="${PLAN_FILE:-$SCRIPT_DIR/install-image-plan.sh}"
KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
KUBECONFIG_DEFAULT="/home/k8s/kube/config/kubeconfig"
export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_DEFAULT}"

TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
POLL_SECONDS="${POLL_SECONDS:-5}"
NAMESPACE="${NAMESPACE:-kube-system}"
STEP_NAME="${STEP:-}"
GROUPS_CSV="${PREFETCH_GROUPS:-}"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--group <name>]... [--step <step>]

Env:
  PLAN_FILE=.../install-image-plan.sh
  PREFETCH_GROUPS=g1,g2
  STEP=<step-name>
  TIMEOUT_SECONDS=900
  POLL_SECONDS=5
  NAMESPACE=kube-system
  KUBECTL=/home/k8s/kube/kubectl
  KUBECONFIG=/home/k8s/kube/config/kubeconfig
USAGE
}

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "ERROR: PLAN_FILE not found: $PLAN_FILE" >&2
  exit 1
fi
source "$PLAN_FILE"

requested_groups=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --group)
      shift
      requested_groups+=("${1:-}")
      ;;
    --step)
      shift
      STEP_NAME="${1:-}"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift || true
done

if [[ -n "$GROUPS_CSV" ]]; then
  IFS=',' read -r -a env_groups <<< "$GROUPS_CSV"
  requested_groups+=("${env_groups[@]}")
fi

if [[ -n "$STEP_NAME" ]]; then
  step_groups="$(plan_groups_for_step "$STEP_NAME")"
  [[ -n "$step_groups" ]] || {
    echo "ERROR: no groups mapped for step '$STEP_NAME'" >&2
    exit 1
  }
  for g in $step_groups; do
    requested_groups+=("$g")
  done
fi

if [[ ${#requested_groups[@]} -eq 0 ]]; then
  echo "ERROR: no groups selected. pass --group or --step" >&2
  exit 1
fi

groups=()
declare -A seen_group
for g in "${requested_groups[@]}"; do
  [[ -z "$g" ]] && continue
  [[ -n "${IMAGE_GROUPS[$g]:-}" ]] || {
    echo "ERROR: unknown group '$g'" >&2
    exit 1
  }
  if [[ -z "${seen_group[$g]:-}" ]]; then
    groups+=("$g")
    seen_group[$g]=1
  fi
done

images=()
declare -A seen_image
for g in "${groups[@]}"; do
  for img in ${IMAGE_GROUPS[$g]}; do
    [[ -z "$img" ]] && continue
    # local-build-output entries are not pullable external refs
    if [[ "$img" == registry.hierocracy.home:5000/* ]]; then
      continue
    fi
    if [[ -z "${seen_image[$img]:-}" ]]; then
      images+=("$img")
      seen_image[$img]=1
    fi
  done
done

if [[ ${#images[@]} -eq 0 ]]; then
  echo "No images selected for prefetch."
  exit 0
fi

sanitize_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's#[^a-z0-9]+#-#g' | sed -E 's#^-+|-+$##g' | cut -c1-45
}

wait_ready() {
  local ns="$1"
  local ds="$2"
  local timeout="$3"
  local start now elapsed desired ready

  start="$(date +%s)"
  while true; do
    now="$(date +%s)"
    elapsed=$((now - start))
    if (( elapsed > timeout )); then
      echo "ERROR: timeout waiting for DaemonSet/$ds readiness" >&2
      return 1
    fi

    desired="$($KUBECTL -n "$ns" get ds "$ds" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)"
    ready="$($KUBECTL -n "$ns" get ds "$ds" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)"

    desired="${desired:-0}"
    ready="${ready:-0}"

    if [[ "$desired" =~ ^[0-9]+$ ]] && [[ "$ready" =~ ^[0-9]+$ ]] && (( desired > 0 )) && (( ready >= desired )); then
      return 0
    fi
    sleep "$POLL_SECONDS"
  done
}

prefetch_image() {
  local img="$1"
  local name ds
  name="$(sanitize_name "$img")"
  ds="image-prefetch-${name}"

  echo "[PREFETCH] image=$img"

  $KUBECTL apply -f - <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ${ds}
  namespace: ${NAMESPACE}
spec:
  selector:
    matchLabels:
      app: ${ds}
  template:
    metadata:
      labels:
        app: ${ds}
    spec:
      tolerations:
      - operator: Exists
      nodeSelector:
        kubernetes.io/os: linux
      containers:
      - name: prefetch
        image: ${img}
        imagePullPolicy: IfNotPresent
        command: ["/bin/sh", "-c", "sleep 600"]
YAML

  wait_ready "$NAMESPACE" "$ds" "$TIMEOUT_SECONDS"

  $KUBECTL -n "$NAMESPACE" delete ds "$ds" --wait=true --timeout=120s >/dev/null
}

echo "Prefetch groups: ${groups[*]}"
echo "Prefetch images: ${#images[@]}"
for img in "${images[@]}"; do
  prefetch_image "$img"
done

echo "Node image prefetch complete."
