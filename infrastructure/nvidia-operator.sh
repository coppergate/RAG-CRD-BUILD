#!/bin/bash
# nvidia-operator.sh — NVIDIA GPU Operator for the external GPU node (Talos-aware)
#
# AUTHORITATIVE. This script is the single source of truth for the GPU operator
# and for the GPU node labels the RAG stack depends on. The logic was previously
# duplicated in kubernetes-setup/new-setup-external-gpu/52-install-gpu-operator.sh
# (since deleted in e1d54a4), and complete-build's copy had drifted into the WORSE
# of the two — it was missing mig.strategy=none and devicePlugin.config.default, so
# running it would undo the tuned install. That divergence is resolved here.
#
# ── Hardware, verified on the live node 2026-09-13 ───────────────────────────
# inference-0 now holds TWO IDENTICAL cards:
#
#   idx  UUID                                      name             mem      cc
#   0    GPU-ce06ba79-6e2e-b16e-e326-3ba4747c6ecb  Tesla PG500-216  32768MiB 7.0  05:00.0
#   1    GPU-1b623f18-4c2c-ea54-ecb7-37c9f03761e5  Tesla PG500-216  32768MiB 7.0  81:00.0
#
# driver 580.126.16. 'Tesla PG500-216' is a BOARD CODE, not a marketing name —
# the driver falls back to it when it has no SKU string. Do not grep for 'V100'.
#
# The 2x Tesla P4 8GB cards are GONE. That retires the whole heterogeneous
# workaround this script used to carry: per-card UUID node labels, pods pinning
# NVIDIA_VISIBLE_DEVICES and deliberately NOT requesting nvidia.com/gpu, and the
# gpu-heterogeneous / gpu-pool-mixed advisory labels. With a uniform pool GFD
# tells the truth and ORDINARY 'nvidia.com/gpu: 1' REQUESTS ARE THE SUPPORTED
# MECHANISM — they also restore the scheduler accounting that pin-by-UUID
# bypassed, so two pods can no longer double-book one card.
#
# nvidia-smi topo -m reports SYS between the two cards (GPU0 on NUMA 0, GPU1 on
# NUMA 1): PCIe plus the cross-socket interconnect, NO NVLINK. Fine for the
# one-card-per-pod topology; a material penalty for any tensor-parallel plan.
#
# Rationale, the two approaches that failed, and the device-plugin limitation
# behind them are preserved in the historical appendix of
# kubernetes-setup/new-setup-external-gpu/EXTERNAL-NODE-SETUP.md. They are still
# true and still non-obvious; read them before reintroducing UUID pinning.
#
# Repo boundary: kubernetes-setup owns Talos-level node provisioning (machine
# config, kernel modules, driver extensions, enrolment). complete-build owns
# everything that is a Kubernetes object — this operator, the RuntimeClass, the
# device-plugin ConfigMap, the validation-fix DaemonSet, and the GPU node labels.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

NAMESPACE="gpu-operator"
RELEASE_NAME="gpu-operator"
GPU_OPERATOR_CHART_VERSION="${GPU_OPERATOR_CHART_VERSION:-25.10.1}"
TIMEOUT_SECS="${TIMEOUT_SECS:-600}"

# Whether to advertise nvidia.com/gpu at all.
#
# MUST stay true. This inverted on 2026-09-13: with two identical cards,
# requesting 'nvidia.com/gpu: 1' is how a workload gets a GPU here, and
# allocatable=2 is what keeps two pods on two distinct cards. The previous note
# said nothing should request the resource — that was a consequence of the mixed
# pool (a request could be handed an 8GB P4) and no longer applies.
#
# Setting this false removes the resource from the node, which now makes every
# GPU workload unschedulable rather than merely un-accounted. DCGM metrics and
# the driver are unaffected either way.
DEVICE_PLUGIN_ENABLED="${DEVICE_PLUGIN_ENABLED:-true}"

# GPU inventory discovery.
#
# No per-card UUIDs any more — nothing pins a card, so nothing needs one. What
# is still worth discovering is HOW MANY cards there are and whether they are
# actually uniform, because the one-card-per-pod topology and every 32GB VRAM
# budget downstream depend on that being true. Capacity is a discovered fact,
# not configuration (same lesson as the node-size label in OPERATIONS.md 1.10).
#
# GPU_EXPECTED_COUNT is a fallback AND an assertion: if discovery finds a
# different number, or finds a card that is not 32GB/sm_7x, the script warns
# loudly rather than labelling a claim it cannot support.
GPU_INVENTORY_DISCOVER="${GPU_INVENTORY_DISCOVER:-true}"
GPU_EXPECTED_COUNT="${GPU_EXPECTED_COUNT:-2}"

# Schema revision for the hierocracy.home/gpu-* label set. Bumped to 2 when the
# mixed-pool labels were retired. It is the idempotency predicate below: rev 1
# labels (gpu-p4-*, gpu-heterogeneous, gpu-pool-mixed, gpu-*-uuid) must be
# actively unset, and a marker alone cannot tell you which schema is on the node.
GPU_LABEL_REV="2"

source "$BASE_DIR/scripts/journal-helper.sh"
init_journal

require_cmd() {
  local c="$1"
  if ! command -v "$c" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $c" >&2
    exit 1
  fi
}

require_cmd "$KUBECTL"
require_cmd helm

echo "[NVIDIA] Validating Kubernetes API access..."
"$KUBECTL" version >/dev/null 2>&1

# Verify command per OPERATIONS.md 1.8.2: the journal and the cluster have
# independent lifetimes, and the inventory probe below runs IN this namespace
# because it needs enforce=privileged. A stale marker here would break it.
if ! is_step_done "nvidia-namespace" "$KUBECTL" get ns "$NAMESPACE"; then
  echo "[NVIDIA] Ensuring namespace and Pod Security labels"
  "$KUBECTL" get ns "$NAMESPACE" >/dev/null 2>&1 || "$KUBECTL" create namespace "$NAMESPACE"
  "$KUBECTL" label --overwrite namespace "$NAMESPACE" \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/enforce-version=latest \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged
  mark_step_done "nvidia-namespace"
fi

if ! is_step_done "nvidia-runtimeclass"; then
  echo "[NVIDIA] Applying RuntimeClass 'nvidia'"
  "$KUBECTL" apply -f "$SCRIPT_DIR/nvidia-runtimeclass.yaml"
  mark_step_done "nvidia-runtimeclass"
fi

if ! is_step_done "nvidia-talos-config"; then
  echo "[NVIDIA] Applying Talos-specific device plugin config"
  "$KUBECTL" apply -n "$NAMESPACE" -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin-config
data:
  config.yaml: |
    version: v1
    flags:
      failOnInitError: true
      # 'none' — the V100 does not support MIG, so this is simply correct.
      #
      # Keep it, but know that setting it HERE is not what makes it effective:
      # the plugin resolves the MIG_STRATEGY env var ABOVE its config file, and
      # the operator sets that env from the Helm value. So mig.strategy in the
      # Helm values below is the load-bearing one; this is the belt to its
      # braces. (The original reason was to stop GFD collapsing the mixed
      # V100+P4 pool onto a single product — that pool is gone as of 2026-09-13,
      # but the env-above-config mechanism is unchanged and still a trap.)
      migStrategy: none
      deviceDiscoveryStrategy: nvml
    #
    # REMOVED — nvidiaDriverRoot: / and nvidiaDevRoot: /
    # Harmless only while this ConfigMap was being ignored (see the 'default'
    # key in the Helm values below). Now that it is actually consumed, they are
    # wrong: '/' does not exist as a driver root on Talos. The plugin default of
    # /run/nvidia/driver is the layout nvidia-talos-validation-fix builds.
    #
    # Per-product resource naming ('resources:') is UNIMPLEMENTED in plugin
    # v0.19.3 — it logs "Customizing the 'resources' field is not yet supported
    # in the config. Ignoring..." and carries on. Every GPU on the node lands in
    # one nvidia.com/gpu pool regardless.
    #
    # That no longer matters here (one uniform pool is what we want), but it is
    # why the mixed pool could not be split, and it is the first thing anyone
    # will reach for if a non-uniform card is ever added back. Full history:
    # kubernetes-setup/new-setup-external-gpu/EXTERNAL-NODE-SETUP.md, historical
    # appendix.
    #
    # DO NOT add an empty 'sharing: timeSlicing: {}' block. It fails config
    # parsing with "no resources specified", the plugin will not start, and
    # nvidia.com/gpu drops to 0. This was previously present and inert; it only
    # became fatal once 'default: config.yaml' made the file load. Re-add only
    # with real content, e.g.:
    #   sharing:
    #     timeSlicing:
    #       resources:
    #       - name: nvidia.com/gpu
    #         replicas: 2
EOF

  echo "[NVIDIA] Applying Talos validation-fix DaemonSet"
  "$KUBECTL" apply -n "$NAMESPACE" -f - <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-talos-validation-fix
  labels:
    app: nvidia-talos-validation-fix
spec:
  selector:
    matchLabels:
      name: nvidia-talos-validation-fix
  template:
    metadata:
      labels:
        name: nvidia-talos-validation-fix
    spec:
      nodeSelector:
        gpu: "true"
      hostPID: true
      tolerations:
      - operator: Exists
      containers:
      - name: validation-fix
        image: registry.hierocracy.home:5000/busybox:1.36
        command:
        - sh
        - -c
        - |
          while true; do
            mkdir -p /run/nvidia/validations /run/nvidia/driver/usr
            # On Talos, /usr/local is accessible from the host.
            # This pod needs to create symlinks in /run/nvidia so the validator thinks the driver is ready.
            # We use absolute paths that point to /host since the validator and device plugin mount the host root at /host.
            ln -sfn /host/usr/local/bin /run/nvidia/driver/usr/bin
            ln -sfn /host/usr/local/glibc/usr/lib /run/nvidia/driver/usr/lib64
            touch /run/nvidia/validations/driver-ready
            touch /run/nvidia/validations/toolkit-ready
            touch /run/nvidia/validations/cuda-ready
            sleep 30
          done
        securityContext:
          privileged: true
        volumeMounts:
        - name: run-nvidia
          mountPath: /run/nvidia
        - name: host-root
          mountPath: /host
          readOnly: true
      volumes:
      - name: run-nvidia
        hostPath:
          path: /run/nvidia
          type: DirectoryOrCreate
      - name: host-root
        hostPath:
          path: /
EOF
  mark_step_done "nvidia-talos-config"
fi

# ── GPU node labels ──────────────────────────────────────────────────────────
# Publishes gpu=true (load-bearing) plus a small, auditable inventory: how many
# cards, how many of them are the 32GB/sm_7x kind, and which label schema wrote
# it. Re-run this script after any GPU is added, removed or reseated.
#
# NO PER-CARD UUID LABELS. They existed so workloads could pin a card with
# NVIDIA_VISIBLE_DEVICES and skip requesting nvidia.com/gpu, which was the only
# way to keep a 32B model off an 8GB P4. With a uniform pool that trick is a
# pure regression — it bypasses scheduler accounting, so two pods can pin the
# same card and fight over VRAM with Kubernetes believing both are fine.
#
# Custom domain prefix so these cannot be confused with, or overwritten by, the
# nvidia.com/* labels GFD manages.

# Predicate for the idempotency guard: does the node already carry THIS label
# schema? A journal marker cannot answer that — rev 1 wrote labels that must now
# be actively unset, and a marker looks identical either way.
#
# This is a function rather than an inline command for two reasons: 'kubectl get
# node -l X -o name' exits 0 even when nothing matches, so emptiness has to be
# tested explicitly; and the previous revision tried to do that with
#   is_step_done "nvidia-gpu-labels" "$KUBECTL" get node -l ... -o name | grep -q node
# where bash binds the pipe to is_step_done's OWN stdout, not to kubectl's. The
# verify therefore tested is_step_done's log message for the string "node" and
# always failed, so the guard never skipped anything. Idempotent, so harmless —
# but it was not doing what it read as doing. (Found 2026-09-13.)
gpu_labels_at_current_rev() {
  local out
  out=$("$KUBECTL" get node -l "hierocracy.home/gpu-inventory-rev=${GPU_LABEL_REV}" \
          -o name 2>/dev/null || true)
  [[ -n "$out" ]]
}

if ! is_step_done "nvidia-gpu-labels-v${GPU_LABEL_REV}" gpu_labels_at_current_rev; then
  echo "[NVIDIA] Publishing GPU inventory labels (schema rev ${GPU_LABEL_REV})"

  GPU_NODE=$("$KUBECTL" get nodes -l role=inference-node -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -z "$GPU_NODE" ]]; then
    echo "ERROR: no node carries role=inference-node. scripts/setup-node-labels.sh" >&2
    echo "       should have applied it before this script runs." >&2
    exit 1
  fi

  # Inventory probe. nvidia-smi cannot be invoked directly on Talos, so shell
  # out through a throwaway privileged pod that chroots into the host userspace.
  #
  # -n "$NAMESPACE" IS LOAD-BEARING. The previous revision omitted it, so the
  # pod landed in 'default', which this cluster admits at PodSecurity
  # 'baseline' — privileged, hostPID and hostPath are all rejected there:
  #   Error from server (Forbidden): pods "gpu-uuid-probe-NNN" is forbidden:
  #   violates PodSecurity "baseline:latest": host namespaces (hostPID=true),
  #   hostPath volumes, privileged
  # '2>/dev/null || echo ""' swallowed it, so discovery had NEVER once succeeded
  # and every run silently used the hardcoded fallbacks (found 2026-09-13).
  # $NAMESPACE carries enforce=privileged from the first step of this script.
  #
  # Fields: index, uuid, name, memory.total, compute_cap — e.g.
  #   0, GPU-ce06ba79-..., Tesla PG500-216, 32768 MiB, 7.0
  # Classify on memory and compute capability, NOT on the name: these cards
  # enumerate as the board code 'Tesla PG500-216' with no 'V100' in it.
  GPU_COUNT=""
  GPU_32G_COUNT=""
  if [[ "$GPU_INVENTORY_DISCOVER" == "true" ]]; then
    echo "[NVIDIA] Discovering GPU inventory on $GPU_NODE..."
    SMI_QUERY="--query-gpu=index,uuid,name,memory.total,compute_cap"
    SMI_OUT=$("$KUBECTL" run "gpu-inventory-probe-$$" -n "$NAMESPACE" --rm -i --restart=Never \
      --image="${REGISTRY_PREFIX:-hierophant.hierocracy.home:5000}/busybox:1.36" \
      --overrides="{\"spec\":{\"nodeName\":\"$GPU_NODE\",\"hostPID\":true,\"tolerations\":[{\"operator\":\"Exists\"}],\"containers\":[{\"name\":\"p\",\"image\":\"${REGISTRY_PREFIX:-hierophant.hierocracy.home:5000}/busybox:1.36\",\"command\":[\"chroot\",\"/host\",\"/usr/local/bin/nvidia-smi\",\"$SMI_QUERY\",\"--format=csv,noheader\"],\"securityContext\":{\"privileged\":true},\"volumeMounts\":[{\"name\":\"h\",\"mountPath\":\"/host\"}]}],\"volumes\":[{\"name\":\"h\",\"hostPath\":{\"path\":\"/\"}}]}}" \
      --timeout=180s 2>/dev/null || echo "")

    GPU_COUNT=$(echo "$SMI_OUT" | grep -cE '^[0-9]+, *GPU-' || true)
    GPU_32G_COUNT=$(echo "$SMI_OUT" \
      | awk -F', *' '$2 ~ /^GPU-/ && $5 ~ /^7\./ && ($4+0) >= 32000 {n++} END {print n+0}')

    if [[ "${GPU_COUNT:-0}" -gt 0 ]]; then
      echo "  discovered ${GPU_COUNT} GPU(s), ${GPU_32G_COUNT} of them >=32GB/sm_7x:"
      # Filter to GPU rows only. 'kubectl run --rm' writes its "pod ... deleted"
      # notice to STDOUT, not stderr, so it is inside $SMI_OUT despite the
      # 2>/dev/null. Both parsers above already ignore it (they anchor on an
      # index followed by GPU-<uuid>); this keeps it out of the install log too.
      echo "$SMI_OUT" | grep -E '^[0-9]+, *GPU-' | sed 's/^/    /'
    else
      echo "  WARNING: inventory probe returned nothing. Falling back to" >&2
      echo "           GPU_EXPECTED_COUNT=${GPU_EXPECTED_COUNT}. The labels below are then an" >&2
      echo "           ASSUMPTION, not a measurement — verify with 'nvidia-smi -L'." >&2
      GPU_COUNT="$GPU_EXPECTED_COUNT"
      GPU_32G_COUNT="$GPU_EXPECTED_COUNT"
    fi
  else
    echo "[NVIDIA] Inventory discovery disabled — using GPU_EXPECTED_COUNT=${GPU_EXPECTED_COUNT}"
    GPU_COUNT="$GPU_EXPECTED_COUNT"
    GPU_32G_COUNT="$GPU_EXPECTED_COUNT"
  fi

  # Two assertions worth shouting about, because the topology downstream assumes
  # both: one card per pod with 'nvidia.com/gpu: 1', and 32GB of VRAM per card.
  if [[ "$GPU_COUNT" != "$GPU_EXPECTED_COUNT" ]]; then
    echo "  WARNING: found ${GPU_COUNT} GPU(s) but GPU_EXPECTED_COUNT=${GPU_EXPECTED_COUNT}." >&2
    echo "           Cards were added or removed. Re-check the per-pod GPU requests and" >&2
    echo "           the VRAM budgets before deploying inference workloads." >&2
  fi
  if [[ "$GPU_32G_COUNT" != "$GPU_COUNT" ]]; then
    echo "  WARNING: $((GPU_COUNT - GPU_32G_COUNT)) of ${GPU_COUNT} card(s) are NOT >=32GB/sm_7x." >&2
    echo "           THE POOL IS NO LONGER UNIFORM. Ordinary nvidia.com/gpu requests can" >&2
    echo "           then hand a large model a small card, which is exactly the failure" >&2
    echo "           the retired UUID-pinning workaround existed to prevent. Read the" >&2
    echo "           historical appendix in EXTERNAL-NODE-SETUP.md before proceeding." >&2
  fi

  # gpu=true is LOAD-BEARING, not inventory: the validation-fix DaemonSet and the
  # devicePlugin / gfd / dcgmExporter Helm nodeSelectors all select on it. Without
  # it those four workloads are unschedulable and the GPU never becomes usable.
  #
  # It is normally applied by Talos machine.nodeLabels in the sibling repo's
  # configs/patch-inference-0.yaml. Asserting it here removes that cross-repo
  # dependency, exactly as the UUID labels do — this script must be sufficient on
  # its own. kubectl label is idempotent, so re-asserting a Talos-set label is a
  # no-op. (Superseded 55-label-gpu-nodes.sh, which also set gpu-count and
  # nvidia.com/gpu.present; the latter is GFD's to manage and is not re-asserted.)
  "$KUBECTL" label --overwrite node "$GPU_NODE" gpu=true "gpu-count=${GPU_COUNT}"

  # Retire the rev-1 mixed-pool labels.
  #
  # DROPPING A LABEL FROM THIS SCRIPT DOES NOT REMOVE IT FROM A LIVE NODE. Without
  # an explicit unset the stale claims outlive the hardware, and they are exactly
  # the kind a human or a manifest would trust: gpu-p4-*-uuid naming cards that are
  # no longer seated, gpu-heterogeneous=true on a uniform pool, and gpu-v100-uuid
  # inviting the pin-by-UUID pattern that now breaks scheduler accounting.
  #
  # The trailing '-' is kubectl's remove-label syntax. Unsetting an absent label
  # is not an error, so this is safe on a fresh node; '|| true' covers the node
  # being unreachable mid-run.
  "$KUBECTL" label node "$GPU_NODE" \
    hierocracy.home/gpu-p4-count- \
    hierocracy.home/gpu-p4-0-uuid- \
    hierocracy.home/gpu-p4-1-uuid- \
    hierocracy.home/gpu-v100-uuid- \
    hierocracy.home/gpu-heterogeneous- \
    hierocracy.home/gpu-pool-mixed- \
    hierocracy.home/gpu-labels-describe- 2>/dev/null || true

  # What is left is measured, not asserted. gpu-32gb-count is deliberately named
  # for the PROPERTY (>=32GB, sm_7x) rather than for 'v100': these cards report
  # the board code 'Tesla PG500-216', and a label that says v100 would be another
  # unverifiable product claim of the sort that already proved wrong once here.
  #
  # gpu-inventory-rev is the guard predicate above. Bump GPU_LABEL_REV if this
  # label set changes shape again, so the next run cannot mistake old for new.
  "$KUBECTL" label --overwrite node "$GPU_NODE" \
    "hierocracy.home/gpu-total-count=${GPU_COUNT}" \
    "hierocracy.home/gpu-32gb-count=${GPU_32G_COUNT}" \
    "hierocracy.home/gpu-inventory-rev=${GPU_LABEL_REV}"

  mark_step_done "nvidia-gpu-labels-v${GPU_LABEL_REV}"
fi

if ! is_step_done "nvidia-cleanup-legacy"; then
  echo "[NVIDIA] Removing legacy NVIDIA releases to avoid conflicts (best effort)"
  if helm -n "$NAMESPACE" status nvidia-device-plugin >/dev/null 2>&1; then
    helm -n "$NAMESPACE" uninstall nvidia-device-plugin || true
  fi
  if helm -n "$NAMESPACE" status nvidia-dcgm-exporter >/dev/null 2>&1; then
    helm -n "$NAMESPACE" uninstall nvidia-dcgm-exporter || true
  fi
  mark_step_done "nvidia-cleanup-legacy"
fi

if ! is_step_done "nvidia-gpu-operator"; then
  echo "[NVIDIA] Installing/Upgrading NVIDIA GPU Operator (Talos-aware)"
  helm repo add nvidia https://nvidia.github.io/gpu-operator >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true

  VALUES_FILE="${SAFE_TMP_DIR}/gpu-operator-values.yaml"
  cat > "$VALUES_FILE" <<EOF
driver:
  enabled: false
toolkit:
  enabled: false
mig:
  # KEEP. The V100 does not support MIG, so 'none' is simply correct, and the
  # chart default is 'single'.
  #
  # THIS is the load-bearing copy of the setting, not the one in the ConfigMap
  # above: it surfaces on the containers as the MIG_STRATEGY env var, and the
  # plugin resolves env ABOVE its config file. Setting migStrategy in the
  # ConfigMap alone cannot fix a wrong value here.
  #
  # The original reason was sharper — on the old mixed pool, 'single' made GFD
  # collapse the node's labels onto one product, observed reporting
  # gpu.product=Tesla-P4 / count=2 and hiding the V100 entirely. The pool is
  # uniform as of 2026-09-13 so that specific failure is retired, but the
  # env-above-config precedence is a property of the plugin and is unchanged.
  strategy: none
operator:
  defaultRuntime: nvidia
  # Run the operator controller on a worker node, not control plane.
  nodeSelector:
    role: storage-node
node-feature-discovery:
  # NFD workers run on EVERY node by default, including control plane.
  # Restrict to inference nodes only — they are the only nodes with GPUs.
  # The 'role=inference-node' label is set by setup-node-labels.sh before
  # this script runs, so it is safe to use as a nodeSelector here.
  # Key is the sub-chart name 'node-feature-discovery', NOT 'nodeFeatureDiscovery'.
  worker:
    nodeSelector:
      role: inference-node
  master:
    nodeSelector:
      role: storage-node
devicePlugin:
  enabled: ${DEVICE_PLUGIN_ENABLED}
  runtimeClassName: nvidia
  nodeSelector:
    gpu: "true"
  config:
    name: nvidia-device-plugin-config
    # REQUIRED. Without 'default' naming the key, the operator ignores the
    # entire ConfigMap and the plugin silently runs on chart defaults — which is
    # what advertised all three GPUs as one pool and lost migStrategy.
    default: config.yaml
  env:
    - name: CDI_ENABLED
      value: "false"
    - name: DEVICE_LIST_STRATEGY
      value: "envvar"
gfd:
  enabled: true
  nodeSelector:
    gpu: "true"
dcgmExporter:
  enabled: true
  nodeSelector:
    gpu: "true"
EOF

  helm upgrade --install "$RELEASE_NAME" nvidia/gpu-operator \
    -n "$NAMESPACE" \
    --create-namespace \
    --version "$GPU_OPERATOR_CHART_VERSION" \
    -f "$VALUES_FILE" \
    --wait \
    --timeout "${TIMEOUT_SECS}s"
  mark_step_done "nvidia-gpu-operator"
fi

echo "[NVIDIA] Waiting for GPU operator deployment rollout"
"$KUBECTL" -n "$NAMESPACE" rollout status deploy/gpu-operator --timeout="${TIMEOUT_SECS}s" || true

echo "[NVIDIA] Waiting for device plugin daemonset rollout"
PLUGIN_DS=$("$KUBECTL" -n "$NAMESPACE" get ds -l app.kubernetes.io/name=nvidia-device-plugin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "${PLUGIN_DS}" ]]; then
  "$KUBECTL" -n "$NAMESPACE" rollout status "ds/${PLUGIN_DS}" --timeout="${TIMEOUT_SECS}s" || true
fi

echo "[NVIDIA] Current GPU operator pods"
"$KUBECTL" -n "$NAMESPACE" get pods -o wide || true

echo "[NVIDIA] Node allocatable GPU view"
"$KUBECTL" get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' || true
echo ""

# ── Post-install audit ───────────────────────────────────────────────────────
# Printed on EVERY run, including runs where the label step was skipped, because
# a skipped step is exactly when a stale claim goes unnoticed.
#
# allocatable nvidia.com/gpu is the number that matters: the one-card-per-pod
# topology needs it to equal the physical card count. If it reads 0 with the
# plugin pods Running, suspect the empty 'sharing: timeSlicing: {}' trap noted
# in the ConfigMap above.
#
# GFD's nvidia.com/gpu.* labels are RECORDED, NOT ASSERTED. They were observed
# lying on this node while the pool was mixed, and gpu.product reports the board
# code rather than a marketing name. Reconcile them by eye; do not gate on them.
GPU_NODE_AUDIT=$("$KUBECTL" get nodes -l role=inference-node \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$GPU_NODE_AUDIT" ]]; then
  echo "[NVIDIA] GPU inventory audit for ${GPU_NODE_AUDIT}"
  echo "  allocatable nvidia.com/gpu : $("$KUBECTL" get node "$GPU_NODE_AUDIT" \
    -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "<unset>")"
  echo "  gpu-* node labels:"
  "$KUBECTL" get node "$GPU_NODE_AUDIT" -o json 2>/dev/null \
    | python3 -c 'import json,sys
labels = json.load(sys.stdin)["metadata"]["labels"]
stale = ("p4", "heterogeneous", "pool-mixed", "uuid", "labels-describe")
for k in sorted(labels):
    if "gpu" not in k.lower():
        continue
    flag = "  <-- STALE rev-1 LABEL, should have been unset" \
           if any(t in k.lower() for t in stale) else ""
    print(f"    {k}={labels[k]}{flag}")' || echo "    (unavailable)"
fi
