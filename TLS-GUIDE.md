# TLS Management Guide

This guide describes how to manage TLS certificates and trust within the Hierocracy RAG cluster environment.

## 1. Creating a TLS Certificate for a Domain

To create a new certificate for a service, define a `Certificate` resource that uses the `hierocracy-ca-issuer` ClusterIssuer.

### Step 1: Create the Certificate Manifest
Create a file (e.g., `my-service-tls.yaml`):

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-service-cert
  namespace: rag-system
spec:
  secretName: my-service-tls
  duration: 8760h # 1 year
  renewBefore: 720h # 30 days
  subject:
    organizations:
      - Hierocracy
  commonName: my-service.rag-system.svc.cluster.local
  isCA: false
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    size: 2048
  usages:
    - server auth
    - client auth
  dnsNames:
    - my-service
    - my-service.rag-system
    - my-service.rag-system.svc
    - my-service.rag-system.svc.cluster.local
    - my-service.rag.hierocracy.home
  issuerRef:
    name: hierocracy-ca-issuer
    kind: ClusterIssuer
    group: cert-manager.io
```

### Step 2: Apply the Manifest
Execute the command on **hierophant**:

```bash
export KUBECONFIG=/home/k8s/kube/config/kubeconfig
/home/k8s/kube/kubectl apply -f my-service-tls.yaml
```

### Step 3: Verify the Certificate
Check the status of the certificate:

```bash
/home/k8s/kube/kubectl get certificate -n rag-system my-service-cert
```

---

## 2. Adding a CA to Satisfy Trust by Local Services

When running services outside the cluster (like the Flutter UI on the development VM), you must trust the Root CA that issues the cluster certificates.

### Step 1: Extract the Root CA Certificate
Run this on **hierophant** to get the CA certificate:

```bash
export KUBECONFIG=/home/k8s/kube/config/kubeconfig
/home/k8s/kube/kubectl get secret -n cert-manager hierocracy-root-ca-secret \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > hierocracy-root-ca.crt
```

### Step 2: Install the CA on the Development VM (Fedora)
Copy the file to the VM and run:

```bash
# Copy to the anchors directory
sudo cp hierocracy-root-ca.crt /etc/pki/ca-trust/source/anchors/

# Update the trust store
sudo update-ca-trust extract
```

### Step 3: Verify Trust
Use `curl` or `openssl` to verify that the connection is now trusted:

```bash
curl -v https://rag-admin-api.rag.hierocracy.home/api/health/all
# Or
openssl s_client -connect rag-admin-api.rag.hierocracy.home:443 -servername rag-admin-api.rag.hierocracy.home < /dev/null 2>&1 | grep "Verification: OK"
```

---

## 3. Adding Additional SAN (Subject Alternative Names) to a Certificate

To add more domains or aliases to an existing certificate:

### Step 1: Update the Certificate Manifest
Modify the `dnsNames` list in your `Certificate` YAML file:

```yaml
spec:
  dnsNames:
    - existing-name.example.com
    - new-alias.rag.hierocracy.home  # <-- Add the new SAN here
```

### Step 2: Re-apply the Manifest
Apply the updated file:

```bash
export KUBECONFIG=/home/k8s/kube/config/kubeconfig
/home/k8s/kube/kubectl apply -f rag-system-tls.yaml
```

### Step 3: Verify the Update
Cert-manager will automatically re-issue the certificate. Verify the SANs in the newly issued secret:

```bash
/home/k8s/kube/kubectl get secret -n rag-system rag-admin-api-tls -o yaml | grep "cert-manager.io/alt-names"
```

Traefik and other services using this secret will automatically pick up the new certificate within a few seconds.
