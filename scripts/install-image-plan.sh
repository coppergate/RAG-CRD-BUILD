#!/bin/bash
# install-image-plan.sh
# Explicit image dependency plan for setup-complete step orchestration.

set -Eeuo pipefail

declare -A IMAGE_GROUPS
IMAGE_GROUPS[bootstrap]="busybox:1.37.0 busybox:1.36 amazon/aws-cli:2.34.4 martizih/kaniko:v1.27.0 gcr.io/kaniko-project/executor:v1.24.0 quay.io/operator-framework/olm@sha256:e74b2ac57963c7f3ba19122a8c31c9f2a0deb3c0c5cac9e5323ccffd0ca198ed quay.io/operator-framework/configmap-operator-registry:latest quay.io/operatorhubio/catalog:latest quay.io/jetstack/cert-manager-cainjector:v1.19.2 quay.io/jetstack/cert-manager-controller:v1.19.2 quay.io/jetstack/cert-manager-acmesolver:v1.19.2 quay.io/jetstack/cert-manager-webhook:v1.19.2 registry.k8s.io/metrics-server/metrics-server:v0.8.1 ghcr.io/headlamp-k8s/headlamp:v0.41.0 kubernetesui/dashboard:v2.7.0 kubernetesui/metrics-scraper:v1.0.8"
# The live CSI sidecar versions are the ROOK_CSI_*_IMAGE pins in
# infrastructure/rook-ceph/operator.yaml (v8.2.1 / v4.8.1 / v0.13.0) — that
# manifest, not the unused rook helm chart values.yaml, is what the operator
# reads. The trailing v6.3.0 / v4.8.0 / v0.5.0 entries are the older versions
# still referenced by that reference-only values.yaml; they are kept seeded so
# the chart path cannot reach the internet if it is ever reinstated.
IMAGE_GROUPS[storage]="busybox:1.36 docker.io/rook/ceph:v1.18.8 quay.io/ceph/ceph:v19.2.3 quay.io/ceph/ceph:v19 quay.io/cephcsi/ceph-csi-operator:v0.4.1 quay.io/cephcsi/cephcsi:v3.15.0 quay.io/csiaddons/k8s-sidecar:v0.13.0 registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.13.0 registry.k8s.io/sig-storage/csi-provisioner:v5.2.0 registry.k8s.io/sig-storage/csi-snapshotter:v8.2.1 registry.k8s.io/sig-storage/csi-attacher:v4.8.1 registry.k8s.io/sig-storage/csi-resizer:v1.13.2 registry.k8s.io/sig-storage/csi-snapshotter:v6.3.0 registry.k8s.io/sig-storage/csi-attacher:v4.8.0 quay.io/csiaddons/k8s-sidecar:v0.5.0"
IMAGE_GROUPS[apm-core]="otel/opentelemetry-collector-contrib:0.147.0 quay.io/prometheus-operator/prometheus-operator:v0.80.1 quay.io/prometheus-operator/prometheus-config-reloader:v0.80.1 grafana/grafana-image-renderer:latest"
IMAGE_GROUPS[pulsar-core]="apachepulsar/pulsar-all:3.0.7 apachepulsar/pulsar-manager:v0.4.0 streamnative/oxia:0.11.9"
IMAGE_GROUPS[registry]="registry:2"
IMAGE_GROUPS[ollama]="ollama/ollama:0.15.6"

# LLM weights, stored in the registry as Ollama OCI artifacts.
# NOT MIRRORABLE BY SKOPEO — these are produced by `ollama pull` + `ollama push`
# in rag-stack/infrastructure/ollama/push-models-to-cluster.sh, not copied from
# a container registry. mirror-all-images.sh therefore excludes this group from
# its default set (same treatment as local-build-output); it is listed here so
# verify-image-preseed.sh can confirm the models are present BEFORE an install
# starts, which is the only point at which internet access is available to fix
# a gap. Keep in sync with the MODELS arrays in push-models-to-cluster.sh and
# pre-pull-models.sh.
IMAGE_GROUPS[ollama-models]="ollama/llama3.1:latest ollama/granite3.1-dense:8b ollama/qwen2.5:32b ollama/qwen3:32b ollama/devstral-small-2:24b ollama/all-minilm:l6-v2 ollama/nomic-embed-text:latest ollama/mxbai-embed-large:latest ollama/llama3.2:3b"
IMAGE_GROUPS[data-services]="qdrant/qdrant:v1.17.0 python:3.9-slim golang:1.25-alpine alpine:3.23.3 ghcr.io/cloudnative-pg/cloudnative-pg:1.25.0 ghcr.io/imusmanmalik/timescaledb-postgis:16-3.5"
IMAGE_GROUPS[helm-runtime]="ghcr.io/neomanexlabs/opencode:1.14.48 alpine/git:latest curlimages/curl:7.78.0 docker.io/grafana/alloy:v1.13.2 docker.io/grafana/loki:3.6.5 docker.io/grafana/loki-canary:3.6.5 docker.io/grafana/tempo:2.9.0 docker.io/kiwigrid/k8s-sidecar:1.30.9 docker.io/nginxinc/nginx-unprivileged:1.29-alpine docker.io/traefik:v3.6.10 ghcr.io/grafana/grafana-operator:v5.22.0 grafana/mimir:3.0.1 grafana/rollout-operator:v0.32.0 memcached:1.6.39-alpine prom/memcached-exporter:v0.15.4 quay.io/k8tz/k8tz:0.19.0 quay.io/prometheus-operator/prometheus-config-reloader:v0.81.0 registry.gitlab.com/purelb/purelb/allocator:v0.13.0 registry.gitlab.com/purelb/purelb/lbnodeagent:v0.13.0 registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.18.0 registry.k8s.io/nfd/node-feature-discovery:v0.18.2 nvcr.io/nvidia/gpu-operator:v25.10.1 nvcr.io/nvidia/k8s/dcgm-exporter:4.4.2-4.7.0-distroless nvcr.io/nvidia/k8s-device-plugin:v0.18.1 nvcr.io/nvidia/cuda:13.0.1-base-ubi9"

# GPU operator operand images, resolved from the ClusterPolicy that chart
# 25.10.1 renders with infrastructure/nvidia-operator.sh's values (the operator
# builds its DaemonSets from that policy at runtime, so `helm template` alone
# does not reveal them). Verified 2026-09-13:
#   ENABLED  -> devicePlugin + gfd  nvcr.io/nvidia/k8s-device-plugin:v0.18.1
#   ENABLED  -> dcgmExporter        nvcr.io/nvidia/k8s/dcgm-exporter:4.4.2-4.7.0-distroless
#   always   -> validator           nvcr.io/nvidia/gpu-operator:v25.10.1
#   always   -> operator init       nvcr.io/nvidia/cuda:13.0.1-base-ubi9
#   disabled -> driver, toolkit (Talos ships the driver; both set false)
# NOT seeded, deliberately:
#   k8s-mig-manager:v0.13.1 — migManager is enabled in the policy but its
#     DaemonSet only lands on nodes labelled nvidia.com/mig.capable=true. The
#     V100 does not support MIG and mig.strategy=none, so it never schedules.
#   kubevirt-gpu-device-plugin:v1.4.0, vgpu-device-manager:v0.4.1 and the
#     vfioManager (another cuda base) are all gated behind
#     sandboxWorkloads.enabled, which the rendered policy sets to false.
# If sandbox workloads or a MIG-capable card ever appear, seed those four.

# Local images built in-cluster or on-host and pushed to the in-cluster registry
# These are not mirrored from external registries by this script.
# Keep in sync with SERVICES/INFRA_SERVICES in rag-stack/build.sh.
IMAGE_GROUPS[local-build-output]="registry.hierocracy.home:5000/build-orchestrator:latest registry.hierocracy.home:5000/llm-gateway:__VERSION__ registry.hierocracy.home:5000/rag-worker:__VERSION__ registry.hierocracy.home:5000/rag-ingestion:__VERSION__ registry.hierocracy.home:5000/db-adapter:__VERSION__ registry.hierocracy.home:5000/qdrant-adapter:__VERSION__ registry.hierocracy.home:5000/object-store-mgr:__VERSION__ registry.hierocracy.home:5000/rag-test-runner:__VERSION__ registry.hierocracy.home:5000/rag-admin-api:__VERSION__ registry.hierocracy.home:5000/memory-controller:__VERSION__ registry.hierocracy.home:5000/prompt-aggregator:__VERSION__ registry.hierocracy.home:5000/embed-gateway:__VERSION__"
# NOT listed: rag-explorer. It has a Dockerfile and a deployment manifest but is
# deliberately excluded from rag-stack/build.sh, so no image is ever produced —
# listing it here would make the pre-seed check fail on an image that by design
# does not exist.

# Base images the Kaniko builds consume as FROM layers. These must exist in the
# registry BEFORE any service build starts (builds are in-cluster and the nodes
# only reach the local registry).
IMAGE_GROUPS[build-bases]="golang:1.25-alpine alpine:3.23.3 python:3.9-slim busybox:1.37.0 martizih/kaniko:v1.27.0 gcr.io/kaniko-project/executor:v1.24.0"

declare -A STEP_IMAGE_GROUPS
STEP_IMAGE_GROUPS[basic]="bootstrap storage helm-runtime"
STEP_IMAGE_GROUPS[apm]="apm-core helm-runtime"
STEP_IMAGE_GROUPS[nvidia]="bootstrap helm-runtime"
STEP_IMAGE_GROUPS[registry]="registry"
STEP_IMAGE_GROUPS[pulsar]="pulsar-core"
STEP_IMAGE_GROUPS[pulsar-init]="pulsar-core"
STEP_IMAGE_GROUPS[build-pipeline-infra]="bootstrap build-bases"
STEP_IMAGE_GROUPS[rag-images]="bootstrap build-bases"
STEP_IMAGE_GROUPS[rag-stack]="data-services ollama local-build-output helm-runtime"

PLAN_STEPS=(basic apm nvidia registry pulsar pulsar-init build-pipeline-infra rag-images rag-stack)

plan_groups() {
  for g in "${!IMAGE_GROUPS[@]}"; do
    echo "$g"
  done | sort
}

plan_steps() {
  printf '%s\n' "${PLAN_STEPS[@]}"
}

plan_images_for_group() {
  local group="$1"
  echo "${IMAGE_GROUPS[$group]:-}"
}

plan_groups_for_step() {
  local step="$1"
  echo "${STEP_IMAGE_GROUPS[$step]:-}"
}

plan_images_for_step() {
  local step="$1"
  local groups
  groups="$(plan_groups_for_step "$step")"
  local g
  for g in $groups; do
    plan_images_for_group "$g"
  done
}

plan_next_step() {
  local step="$1"
  local i
  for ((i=0; i<${#PLAN_STEPS[@]}; i++)); do
    if [[ "${PLAN_STEPS[$i]}" == "$step" ]]; then
      if (( i + 1 < ${#PLAN_STEPS[@]} )); then
        echo "${PLAN_STEPS[$((i+1))]}"
      fi
      return 0
    fi
  done
  return 1
}
