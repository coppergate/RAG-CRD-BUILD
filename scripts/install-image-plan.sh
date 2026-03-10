#!/bin/bash
# install-image-plan.sh
# Explicit image dependency plan for setup-complete step orchestration.

set -Eeuo pipefail

declare -A IMAGE_GROUPS
IMAGE_GROUPS[bootstrap]="busybox:1.37.0 busybox:1.36 amazon/aws-cli:2.34.4 martizih/kaniko:v1.27.0 gcr.io/kaniko-project/executor:v1.24.0 quay.io/operator-framework/olm@sha256:e74b2ac57963c7f3ba19122a8c31c9f2a0deb3c0c5cac9e5323ccffd0ca198ed quay.io/operator-framework/configmap-operator-registry:latest quay.io/operatorhubio/catalog:latest quay.io/jetstack/cert-manager-cainjector:v1.19.2 quay.io/jetstack/cert-manager-controller:v1.19.2 quay.io/jetstack/cert-manager-acmesolver:v1.19.2 quay.io/jetstack/cert-manager-webhook:v1.19.2 registry.k8s.io/metrics-server/metrics-server:v0.8.1 kubernetesui/dashboard:v2.7.0 kubernetesui/metrics-scraper:v1.0.8"
IMAGE_GROUPS[storage]="busybox:1.36 docker.io/rook/ceph:v1.18.8 quay.io/ceph/ceph:v19.2.3 quay.io/ceph/ceph:v19 quay.io/cephcsi/ceph-csi-operator:v0.4.1 quay.io/cephcsi/cephcsi:v3.15.0 quay.io/csiaddons/k8s-sidecar:v0.13.0 registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.13.0 registry.k8s.io/sig-storage/csi-provisioner:v5.2.0 registry.k8s.io/sig-storage/csi-snapshotter:v8.2.1 registry.k8s.io/sig-storage/csi-attacher:v4.8.1 registry.k8s.io/sig-storage/csi-resizer:v1.13.2"
IMAGE_GROUPS[apm-core]="otel/opentelemetry-collector-contrib:0.147.0 quay.io/prometheus-operator/prometheus-operator:v0.80.1 quay.io/prometheus-operator/prometheus-config-reloader:v0.80.1"
IMAGE_GROUPS[pulsar-core]="apachepulsar/pulsar-all:3.0.7 apachepulsar/pulsar-manager:v0.4.0 streamnative/oxia:0.11.9"
IMAGE_GROUPS[registry]="registry:2"
IMAGE_GROUPS[ollama]="ollama/ollama:0.15.6"
IMAGE_GROUPS[data-services]="qdrant/qdrant:v1.17.0 python:3.9-slim golang:1.25-alpine alpine:3.23.3 ghcr.io/cloudnative-pg/cloudnative-pg:1.25.0 ghcr.io/imusmanmalik/timescaledb-postgis:16-3.5"
IMAGE_GROUPS[helm-runtime]="curlimages/curl:7.78.0 docker.io/grafana/alloy:v1.13.2 docker.io/grafana/loki:3.6.5 docker.io/grafana/loki-canary:3.6.5 docker.io/grafana/tempo:2.9.0 docker.io/kiwigrid/k8s-sidecar:1.30.9 docker.io/nginxinc/nginx-unprivileged:1.29-alpine docker.io/traefik:v3.6.10 ghcr.io/grafana/grafana-operator:v5.22.0 grafana/mimir:3.0.1 grafana/rollout-operator:v0.32.0 memcached:1.6.39-alpine prom/memcached-exporter:v0.15.4 quay.io/k8tz/k8tz:0.19.0 quay.io/prometheus-operator/prometheus-config-reloader:v0.81.0 registry.gitlab.com/purelb/purelb/allocator:v0.13.0 registry.gitlab.com/purelb/purelb/lbnodeagent:v0.13.0 registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.18.0 registry.k8s.io/nfd/node-feature-discovery:v0.18.2 nvcr.io/nvidia/gpu-operator:v25.10.1 nvcr.io/nvidia/k8s/dcgm-exporter:4.4.2-4.7.0-distroless nvcr.io/nvidia/k8s-device-plugin:v0.18.1"

# Local images built in-cluster or on-host and pushed to the in-cluster registry
# These are not mirrored from external registries by this script.
IMAGE_GROUPS[local-build-output]="registry.hierocracy.home:5000/build-orchestrator:latest registry.hierocracy.home:5000/llm-gateway:__VERSION__ registry.hierocracy.home:5000/rag-worker:__VERSION__ registry.hierocracy.home:5000/rag-web-ui:__VERSION__ registry.hierocracy.home:5000/rag-ingestion:__VERSION__ registry.hierocracy.home:5000/db-adapter:__VERSION__ registry.hierocracy.home:5000/qdrant-adapter:__VERSION__ registry.hierocracy.home:5000/object-store-mgr:__VERSION__ registry.hierocracy.home:5000/rag-test-runner:__VERSION__"

declare -A STEP_IMAGE_GROUPS
STEP_IMAGE_GROUPS[basic]="bootstrap storage helm-runtime"
STEP_IMAGE_GROUPS[apm]="apm-core helm-runtime"
STEP_IMAGE_GROUPS[nvidia]="bootstrap helm-runtime"
STEP_IMAGE_GROUPS[registry]="registry"
STEP_IMAGE_GROUPS[pulsar]="pulsar-core"
STEP_IMAGE_GROUPS[pulsar-init]="pulsar-core"
STEP_IMAGE_GROUPS[build-pipeline-infra]="bootstrap"
STEP_IMAGE_GROUPS[rag-images]="bootstrap"
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
