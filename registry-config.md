# Registry Configuration & Image Management

This document provides a detailed description of the container registry architecture and the images used in the end-to-end RAG stack setup.

## 1. Registry Architecture

The system uses a dual-registry topology to ensure high availability, fast pulls, and air-gap readiness.

### 1.1 Host Registry (Bootstrap)
- **Address**: `https://10.0.0.1:5000` (`hierophant:5000`)
- **DNS Alias**: `https://registry.hierocracy.home:5000`
- **Purpose**: Acts as the primary mirror for all nodes in the cluster and the initial entry point for bootstrapping the in-cluster registry.
- **Service**: Runs as a Podman container directly on the `hierophant` host.
- **Security**: TLS-enabled using a custom Root CA (trust distributed via Talos).

### 1.2 In-Cluster Registry (Cluster-Native)
- **Namespace**: `container-registry`
- **Service Type**: `LoadBalancer`
- **Address**: `https://172.20.1.26:5000`
- **Internal DNS**: `https://registry.container-registry.svc.cluster.local:5000`
- **Storage**: Rook-Ceph PVC (`registry-pvc`) using the `rook-ceph-block` storage class.
- **Node Affinity**: Scheduled on `storage-node` role (worker nodes).
- **Security**: TLS-enabled via Cert-Manager and the common Root CA.

## 2. Talos Node Configuration

All nodes (control plane, workers, and inference) are patched with `infrastructure/registry/talos-registry-patch.yaml` to ensure they trust and use the local registry.

### 2.1 Host Resolution & Trust
The following entries are added to the `/etc/hosts` of all Talos nodes:
- `10.0.0.1` -> `hierophant.hierocracy.home`, `registry.hierocracy.home`, `hierophant`

The **Root CA** is added to the machine configuration trust store to allow verified HTTPS pulls from both registries.

### 2.2 Registry Mirrors
To optimize image pulls and support air-gapped environments, public registries are mirrored to the local registry:
- `docker.io` -> `https://10.0.0.1:5000`
- `quay.io` -> `https://10.0.0.1:5000`
- `registry.k8s.io` -> `https://10.0.0.1:5000`
- `ghcr.io` -> `https://10.0.0.1:5000`

### 2.3 Secure Registry Access
The cluster now uses verified TLS for all registry communication. The `insecureSkipVerify` flag has been removed across the stack.

## 3. Image Management Lifecycle

The management of images involves mirroring from upstream sources, prefetching to local caches, and backup/restore operations.

### 3.1 Mirroring (scripts/mirror-all-images.sh)
This script is used to copy images from public registries or the local upstream cache (`image-source-cache`) to the `registry.hierocracy.home:5000` repository. It uses `skopeo` for high-performance mirroring.

### 3.2 Prefetching (scripts/prefetch-node-images.sh)
Prefetching ensures that critical images are available in the node-local `containerd` cache before they are requested by pods. This is done via a temporary `DaemonSet` during the bootstrap process.

### 3.3 Caching Strategies
- **Upstream Cache**: `/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/image-source-cache/images/` contains a local directory structure for public images, allowing for rapid mirroring without internet access.
- **Registry Snapshots**: `/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/registry-cache/` contains timestamped bundles of the entire local registry content, managed by `scripts/cache-registry-images.sh`. This is used to preserve the state across cluster rebuilds.

## 4. Image Reference (by Group)

The following image groups are defined in `scripts/install-image-plan.sh`:

### 4.1 bootstrap
- `busybox:1.37.0`, `busybox:1.36`
- `amazon/aws-cli:2.34.4`
- `martizih/kaniko:v1.27.0`, `gcr.io/kaniko-project/executor:v1.24.0`
- `quay.io/operator-framework/olm@sha256:e74b2ac57963c7f3ba19122a8c31c9f2a0deb3c0c5cac9e5323ccffd0ca198ed`
- `quay.io/operator-framework/configmap-operator-registry:latest`
- `quay.io/operatorhubio/catalog:latest`
- `quay.io/jetstack/cert-manager-cainjector:v1.19.2`, `...-controller`, `...-acmesolver`, `...-webhook`
- `registry.k8s.io/metrics-server/metrics-server:v0.8.1`
- `kubernetesui/dashboard:v2.7.0`, `kubernetesui/metrics-scraper:v1.0.8`

### 4.2 storage
- `docker.io/rook/ceph:v1.18.8`
- `quay.io/ceph/ceph:v19.2.3`, `quay.io/ceph/ceph:v19`
- `quay.io/cephcsi/ceph-csi-operator:v0.4.1`, `quay.io/cephcsi/cephcsi:v3.15.0`
- `quay.io/csiaddons/k8s-sidecar:v0.13.0`
- `registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.13.0`, `...-provisioner:v5.2.0`, `...-snapshotter:v8.2.1`, `...-attacher:v4.8.1`, `...-resizer:v1.13.2`

### 4.3 apm-core
- `otel/opentelemetry-collector-contrib:0.147.0`
- `quay.io/prometheus-operator/prometheus-operator:v0.80.1`, `...-config-reloader:v0.80.1`

### 4.4 pulsar-core
- `apachepulsar/pulsar-all:3.0.7`, `apachepulsar/pulsar-manager:v0.4.0`
- `streamnative/oxia:0.11.9`

### 4.5 data-services
- `qdrant/qdrant:v1.17.0`
- `python:3.9-slim`, `golang:1.25-alpine`, `alpine:3.23.3`
- `ghcr.io/cloudnative-pg/cloudnative-pg:1.25.0`, `ghcr.io/imusmanmalik/timescaledb-postgis:16-3.5`

### 4.6 helm-runtime
- `docker.io/grafana/alloy:v1.13.2`, `.../loki:3.6.5`, `.../tempo:2.9.0`
- `docker.io/traefik:v3.6.10`
- `ghcr.io/grafana/grafana-operator:v5.22.0`
- `nvcr.io/nvidia/gpu-operator:v25.10.1`, `.../k8s/dcgm-exporter:4.4.2-4.7.0-distroless`, `.../k8s-device-plugin:v0.18.1`
- `registry.gitlab.com/purelb/purelb/allocator:v0.13.0`, `.../lbnodeagent:v0.13.0`

### 4.7 local-build-output (RAG Stack Services)
These images are built in-cluster and pushed directly to `registry.hierocracy.home:5000`:
- `db-adapter`, `llm-gateway`, `object-store-mgr`, `qdrant-adapter`, `rag-worker`, `rag-web-ui`, `rag-ingestion`, `rag-test-runner`

## 5. Operations & Maintenance

### 5.1 Manual Image Push
To push an image manually to the local registry from a node or `hierophant`:
```bash
podman tag <image> registry.hierocracy.home:5000/<image>:<tag>
podman push --tls-verify=false registry.hierocracy.home:5000/<image>:<tag>
```

### 5.2 Backup and Restore
Use the `cache-registry-images.sh` script to manage registry bundles:
```bash
# Backup
bash scripts/cache-registry-images.sh backup

# Restore
bash scripts/cache-registry-images.sh restore <bundle-dir>
```

### 5.3 Troubleshooting
- **Node Pull Failures**: Verify `talosctl -n <node-ip> get machineconfig` shows the mirrors and `insecureSkipVerify` settings.
- **Registry Unreachable**: Check the registry pod status: `kubectl get pods -n container-registry`.
- **Mirror Lag**: Ensure `scripts/mirror-all-images.sh` has been executed for the required image groups.
