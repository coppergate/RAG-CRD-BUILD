# TLS Security Implementation: RAG Stack

This document details the architecture, creation, and implementation of end-to-end TLS security throughout the RAG stack installation.

## 1. Trust Architecture (Root CA)

The entire cluster's security is anchored on a custom **Root Certificate Authority (CA)** established on the `hierophant` host.

- **Subject**: `CN=Hierocracy Root CA, O=Hierocracy, C=US`
- **Location (Host)**: `/etc/pki/ca-trust/source/anchors/hierocracy-root-ca.crt`
- **Host-Level Distribution**: The Root CA is added to the system trust store on `hierophant` and distributed to all Talos nodes via the `machine.install.extraCerts` configuration in `/mnt/hegemon-share/share/code/kubernetes-setup/configs/talos-registry-patch.yaml`.

## 2. In-Cluster Certificate Management

Within the Kubernetes cluster, TLS certificates are automatically managed and renewed using **cert-manager**.

### 2.1 ClusterIssuer
A `ClusterIssuer` named `hierocracy-ca-issuer` is configured in the `cert-manager` namespace. It uses a Kubernetes secret (`hierocracy-root-ca-secret`) containing the Root CA certificate and private key to issue and sign certificates for all services.

### 2.2 Certificate Resources
Each service requiring TLS has a `Certificate` resource that defines its DNS names (including `*.hierocracy.home` and internal `.svc.cluster.local` names).

| Service | Secret Name | Namespace | Main DNS |
| :--- | :--- | :--- | :--- |
| **LLM Gateway** | `llm-gateway-tls` | `rag-system` | `gateway.hierocracy.home` |
| **RAG Ingestion** | `rag-ingestion-tls` | `rag-system` | `rag-ingestion-service.rag-system.svc` |
| **RAG Web UI** | `rag-web-ui-tls` | `rag-system` | `ui.hierocracy.home` |
| **Qdrant** | `qdrant-tls` | `rag-system` | `qdrant.hierocracy.home` |
| **TimescaleDB** | `timescaledb-server-tls`| `timescaledb` | `timescaledb.hierocracy.home` |
| **Registry** | `in-cluster-registry-tls`| `container-registry`| `registry.hierocracy.home` |
| **Loki Gateway**| `loki-gateway-tls` | `monitoring` | `loki.monitoring.svc` |
| **Mimir Gateway**| `mimir-gateway-tls` | `monitoring` | `mimir.monitoring.svc` |
| **Tempo Push** | `tempo-tls` | `monitoring` | `tempo.monitoring.svc` |

## 3. Trust Distribution & Combined CAs

To ensure all components trust both the registry and the internal services, a combined CA chain is created during installation.

1.  **Extraction**: Installation scripts (e.g., `rag-stack/infrastructure/pulsar/install.sh`) extract the `ca.crt` from the `in-cluster-registry-tls` secret.
2.  **ConfigMap**: These certificates are bundled into a ConfigMap named `registry-ca-cm` in target namespaces (e.g., `rag-system`, `apache-pulsar`).
3.  **Mounting**: Pods mount this ConfigMap as `/etc/ssl/certs/ca-certificates.crt`.
4.  **Environment Variable**: The `SSL_CERT_FILE` environment variable is set to this path, allowing language runtimes (Go, Python) to automatically trust the CA.

## 4. Component-Specific Implementation

### 4.1 Container Registry
- **Host Registry**: Runs on `hierophant:5000` with TLS enabled via Podman.
- **In-Cluster Registry**: Uses `REGISTRY_HTTP_TLS_CERTIFICATE` and `REGISTRY_HTTP_TLS_KEY` env vars pointing to the `in-cluster-registry-tls` secret mount.

### 4.2 Apache Pulsar
- **Protocol**: Secured via `pulsar+ssl://` on port 6651.
- **Configuration**: `tls.enabled: true` in Helm values, integrated with `cert-manager` to generate certificates for proxies, brokers, bookies, and zookeeper nodes.

### 4.3 Qdrant (Vector Database)
- **Configuration**: `enable_tls: true` in `qdrant-config.yaml`.
- **Certificates**: Mounted from the `qdrant-tls` secret into `/qdrant/tls/`.

### 4.4 TimescaleDB (PostgreSQL)
- **Operator**: Managed by CloudNativePG (CNPG).
- **Security**: The `Cluster` resource defines `certificates.serverTLSSecret` pointing to `timescaledb-server-tls`.

### 4.5 LLM Gateway & RAG Services (Go/Python)
- **Server-side**: Services use `ListenAndServeTLS` (Go) or `uvicorn` with `ssl_certfile/ssl_keyfile` (Python) to serve HTTPS.
- **Client-side**:
  - **Go**: Uses the system root CA pool (via `SSL_CERT_FILE`) automatically.
  - **Python**: Explicitly configures the Pulsar client using `tls_trust_certs_file_path=os.getenv("SSL_CERT_FILE")`.

### 4.6 APM Stack (Monitoring)
- **Gateways (Loki/Mimir)**: Use a manual NGINX sidecar/gateway configured with TLS (port 8443 internally, 443 via Service).
- **Tempo**: Configured with a dedicated `tempo-tls` secret for the OTLP/gRPC/HTTPS ingestion endpoint (port 4318).
- **Grafana**: Datasources (Loki, Prometheus, Tempo) are configured with `tlsSkipVerify: true` or explicitly trust the internal CA.
- **Alloy**: DaemonSet agents use `tls_config` with CA trust to push metrics, logs, and traces to the respective gateways.

## 5. Timezone Consistency (k8tz)

To ensure consistent timestamps for logs, metrics, and traces across the cluster, **k8tz** is used for cluster-wide timezone injection.
- **Timezone**: `Europe/London` (BST/GMT).
- **Scope**: Enabled for all namespaces, including `kube-system`, except where explicitly excluded (e.g., `k8tz` itself).
- **Implementation**: Mutating Admission Webhook that injects a `k8tz` init container and the `TZ` environment variable.

## 6. Network Ingress

All external-facing services are exposed via **Traefik** with TLS termination.
- **Entrypoint**: `websecure` (Port 443).
- **Annotation**: `traefik.ingress.kubernetes.io/router.tls: "true"`.
- **Standard Domains**: All routes use the `*.hierocracy.home` suffix for consistency.

## 6. Verification Commands

To verify TLS configuration and trust:

- **Check Certificate Expiry**:
  ```bash
  kubectl get certificate -A
  ```
- **Inspect Certificate Details**:
  ```bash
  kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
  ```
- **Test Connectivity with CA Trust**:
  ```bash
  curl -v --cacert /etc/ssl/certs/ca-certificates.crt https://gateway.hierocracy.home/health
  ```
- **Pulsar TLS Verification**:
  ```bash
  /pulsar/bin/pulsar-client --url pulsar+ssl://pulsar-proxy:6651 produce my-topic --messages "test"
  ```
