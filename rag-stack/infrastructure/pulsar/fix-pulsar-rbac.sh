#!/usr/bin/env bash
# Apply namespaced RBAC to allow kubelets (system:nodes) to create serviceaccounts/token
# in the apache-pulsar namespace, then bounce broker pods to retry token mount.
#
# Usage:
#   chmod +x apply-pulsar-nodes-rbac.sh
#   ./apply-pulsar-nodes-rbac.sh

set -Eeuo pipefail

NS="apache-pulsar"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
REQ_TIMEOUT="20s"
export KUBECONFIG=/home/k8s/kube/config/kubeconfig
KB=/home/k8s/kube/kubectl

# 1) Apply namespaced RBAC (idempotent)
cat <<'YAML' | $KB --request-timeout=20s --validate=false apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: nodes-serviceaccount-token-creator
  namespace: apache-pulsar
rules:
- apiGroups: [""]
  resources: ["serviceaccounts/token"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: nodes-serviceaccount-token-creator-binding
  namespace: apache-pulsar
subjects:
- kind: Group
  name: system:nodes
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: nodes-serviceaccount-token-creator
  apiGroup: rbac.authorization.k8s.io
YAML

# 2) Verify RBAC objects exist
$KB -n apache-pulsar get role nodes-serviceaccount-token-creator -o name
$KB -n apache-pulsar get rolebinding nodes-serviceaccount-token-creator-binding -o name

# 3) Restart affected pods to retry token mount
$KB -n apache-pulsar delete pod -l app=pulsar,component=broker --wait=false || true
$KB -n apache-pulsar delete pod -l app=pulsar,component=autorecovery --wait=false || true

# 4) Wait for readiness (up to 5 minutes)
$KB -n apache-pulsar wait --for=condition=Ready pod -l app=pulsar,component=broker --timeout=5m || true
$KB -n apache-pulsar wait --for=condition=Ready pod -l app=pulsar,component=autorecovery --timeout=5m || true

# 5) Quick status
$KB -n apache-pulsar get pods -o wide