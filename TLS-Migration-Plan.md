# TLS Migration Plan: Secure Registry Configuration

This document outlines the end-to-end changes to move the RAG cluster registry from insecure HTTP to verified TLS.

## Phase 1: Certificate Authority (CA) Establishment

- **Root CA**: Generate a custom Root CA on the `hierophant` host.
- **Subject**: `CN=Hierocracy Root CA, O=Hierocracy, C=US`
- **Location**: `/etc/pki/ca-trust/source/anchors/hierocracy-root-ca.crt` (on hierophant).
- **Host Registry Certs**:
  - SANs: `hierophant.hierocracy.home`, `registry.hierocracy.home`, `10.0.0.1`
  - Location: `/etc/docker/registry/certs/` (on hierophant).

## Phase 2: Host-Level Registry (Bootstrap) Transition

- **Configuration**: Update the Docker Registry configuration on `hierophant` to point to the new certificates.
- **Protocol**: Shift from `http://10.0.0.1:5000` to `https://10.0.0.1:5000`.
- **Validation**: Ensure `curl -u ... --cacert ... https://10.0.0.1:5000/v2/` works from the host.

## Phase 3: Talos Node Trust Chain

- **Machineconfig Patch**: Update `infrastructure/registry/talos-registry-patch.yaml`.
- **Changes**:
  - Add the base64-encoded Root CA to `machine.install.extraCerts`.
  - Replace `insecureSkipVerify: true` with `ca: <BASE64_CERT>` for all mirrors (`docker.io`, `quay.io`, etc.).
  - *Note: Reboot/reinstall required for nodes to fully trust the CA for bootstrap pulls.*

## Phase 4: In-Cluster Registry (Native) TLS

- **Cert-Manager**:
  - Deploy a `ClusterIssuer` (type: CA) using the same Root CA private key.
  - Create a `Certificate` resource for `registry.container-registry.svc.cluster.local`.
- **Registry Deployment**:
  - Mount the TLS secret into the `container-registry` pods.
  - Update `REGISTRY_HTTP_TLS_CERTIFICATE` and `REGISTRY_HTTP_TLS_KEY` env vars.
- **Service**: Point to port 5000 (HTTPS).

## Phase 5: Global Audit & Cleanup of Insecure Flags

Audit and remove the following flags/configurations:

| Component | Files to Modify | Action |
| :--- | :--- | :--- |
| **Prometheus** | `infrastructure/prometheus/prometheus-operator.yaml` | Remove `insecureSkipVerify` from all ServiceMonitors/PodMonitors. |
| **Loki/Tempo** | `infrastructure/APM/*/values.yaml.template` | Set `insecure: false` and point to `https://`. |
| **Kaniko** | `rag-stack/infrastructure/build-pipeline/*` | Remove `--insecure`, `--insecure-pull`, and `--insecure-registry`. |
| **Orchestrator** | `rag-stack/services/build-orchestrator/cmd/orchestrator/main.go` | Remove hardcoded `--insecure` flags from the job template generator. |
| **Ollama** | `rag-stack/infrastructure/ollama/values.yaml` | Set `insecure: false`. |
| **Metrics Server**| `infrastructure/vendor/metrics-server-components.yaml` | Remove `--kubelet-insecure-tls`. |
| **Rook-Ceph** | `infrastructure/rook-ceph/crds.yaml` | Audit for internal insecure calls. |

## Phase 6: Post-Migration Verification

1.  **Talos Pulls**: `talosctl -n <ip> image pulls` verify no HTTPS errors.
2.  **K8s Events**: Check for `ImagePullBackOff` across all namespaces.
3.  **Metrics**: Ensure Prometheus targets are `Up` without TLS verification errors.
