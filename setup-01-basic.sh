
export BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export KUBECTL="/home/k8s/kube/kubectl"

set -e

# this should point to the location of the directory
# which houses some script functions that help with the k8s builds
export config_source_dir="$BASE_DIR"
source "$config_source_dir/scripts/k8s-install-helper-functions.sh"
source "$config_source_dir/scripts/journal-helper.sh"

# Single source of truth for network + registry addressing (flat-LAN design).
source "$config_source_dir/config/network.env"

# Reconcile static manifests (registry prefix, in-cluster registry LB IP) to
# config/network.env before anything is applied. Idempotent.
bash "$config_source_dir/scripts/render-manifests.sh"

# Ensure host trusts the registry CA for secure image mirroring/seeding
bash "$config_source_dir/scripts/setup-host-trust.sh"

init_journal

#fresh k8s cluster
 
# ip r add 10.2.0.0/24 via 172.16.64.32
# nmcli conn 

# to develop operators apply the following 
#./olm.setup.sh

#echo "create a local olm sdk install..."
#operator-sdk olm install --timeout 5m0s

if ! is_step_done "registry-patch"; then
echo "--- 1. Applying Talos Registry Patches (Bootstrap) ---"
# We apply the patch early so that all subsequent pulls can use the hierophant mirror.
# This avoids redundant internet downloads across all cluster nodes.
bash $config_source_dir/infrastructure/registry/apply-patch.sh
mark_step_done "registry-patch"
fi

if ! is_step_done "bootstrap-mirror"; then
echo "--- 2. Mirroring Bootstrap Images to Hierophant Registry ---"
# TARGET_REGISTRY=127.0.0.1:5000 is the local registry on hierophant.
TARGET_REGISTRY=127.0.0.1:5000 bash $config_source_dir/scripts/mirror-all-images.sh --step basic --apply
mark_step_done "bootstrap-mirror"
fi

echo "--- 3. Node Labeling (Idempotent) ---"
bash "$config_source_dir/scripts/setup-node-labels.sh"

# rook-ceph-image-prefetch removed in favor of hierophant registry mirror bootstrap
# This avoids downloading the same image 9 times from the internet.

if ! is_step_done "rook-ceph-operator"; then
echo "install rook-ceph operator"

$KUBECTL get namespace rook-ceph >/dev/null 2>&1 || $KUBECTL create namespace rook-ceph
$KUBECTL label --overwrite namespace rook-ceph  pod-security.kubernetes.io/audit=privileged  pod-security.kubernetes.io/warn=privileged pod-security.kubernetes.io/enforce=privileged

# wipe disks before cluster creation to ensure clean OSDs
if ! is_step_done "rook-ceph-wipe-disks"; then
  bash $config_source_dir/infrastructure/rook-ceph/wipe-disks.sh
  mark_step_done "rook-ceph-wipe-disks"
fi

helm repo add rook-release https://charts.rook.io/release

$KUBECTL apply -f $config_source_dir/infrastructure/rook-ceph/crds.yaml
$KUBECTL apply -f $config_source_dir/infrastructure/rook-ceph/common.yaml
# csi-operator.yaml registers CRDs (CephConnection, OperatorConfig) that Rook v1.18+
# REQUIRES. Rook creates CephConnection/OperatorConfig CRs; ceph-csi-operator reconciles
# those CRs into the actual CSI provisioner deployments (ctrlplugin, nodeplugin).
# Both must run — scaling ceph-csi-controller-manager to 0 prevents CSI from ever deploying.
$KUBECTL apply -f $config_source_dir/infrastructure/rook-ceph/csi-operator.yaml
# CSI defaults must exist BEFORE Rook creates its Driver CRs, so the nodeplugin
# DaemonSet is born tolerating the inference-node GPU taint. Without this the
# GPU Ollama pods cannot mount their rook-cephfs PVC on inference-0.
$KUBECTL apply -f $config_source_dir/infrastructure/rook-ceph/csi-operator-config.yaml
$KUBECTL apply -f $config_source_dir/infrastructure/rook-ceph/operator.yaml

echo "Check the ceph-operator pod"
WaitForPodsRunning "rook-ceph" "rook-ceph-operator" 30
mark_step_done "rook-ceph-operator"
fi

if ! is_step_done "rook-ceph-cluster"; then
echo "Next step the storage CRDs"

$KUBECTL apply -f $config_source_dir/infrastructure/rook-ceph/cluster.yaml
$KUBECTL apply -f $config_source_dir/infrastructure/rook-ceph/filesystem.yaml
$KUBECTL apply -f $config_source_dir/infrastructure/rook-ceph/object.yaml
$KUBECTL apply -f $config_source_dir/infrastructure/rook-ceph/pool.yaml


# ── Wait for Ceph to fully initialize before marking this step done ──────────
# The rook-ceph-cluster step must NOT complete until Ceph is actually ready.
# Everything downstream (registry, APM, Pulsar) needs PVC provisioning to work.
# Sequence: MONs start → MGR starts → OSDs start → Ceph health OK → MDS →
#           StorageClass applied → CSI ctrlplugin deployed → PVC provisioning works.

echo "Waiting for Ceph cluster health (up to 1800s)..."
ceph_elapsed=0
while (( ceph_elapsed < 1800 )); do
    ceph_status=$($KUBECTL -n rook-ceph get cephcluster rook-ceph \
        -o jsonpath='{.status.ceph.health}' 2>/dev/null || echo "UNKNOWN")
    if [[ "$ceph_status" == HEALTH_OK* ]] || [[ "$ceph_status" == HEALTH_WARN* ]]; then
        echo "  Ceph health: $ceph_status (${ceph_elapsed}s)"
        break
    fi
    echo "  Ceph health: ${ceph_status:-UNKNOWN} — waiting 30s... (${ceph_elapsed}s/1800s)"
    sleep 30
    (( ceph_elapsed += 30 )) || true
done
if [[ "$ceph_status" != HEALTH_OK* ]] && [[ "$ceph_status" != HEALTH_WARN* ]]; then
    echo "ERROR: Ceph did not reach healthy state within 1800s. Aborting."
    exit 1
fi

echo "Applying StorageClass..."
$KUBECTL apply -f $config_source_dir/infrastructure/rook-ceph/storageclass.yaml

# ── Wait for ceph-csi-controller-manager (the operator that creates CSI provisioner deployments) ──
echo "Waiting for ceph-csi-controller-manager (up to 300s)..."
csi_op_elapsed=0
while (( csi_op_elapsed < 300 )); do
    avail=$($KUBECTL get deployment -n rook-ceph ceph-csi-controller-manager \
        -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)
    if [[ "$avail" =~ ^[1-9] ]]; then
        echo "  ceph-csi-controller-manager: $avail available (${csi_op_elapsed}s)"
        break
    fi
    if (( csi_op_elapsed % 30 == 0 )); then
        pod_status=$($KUBECTL get pods -n rook-ceph -l "control-plane=ceph-csi-op-controller-manager" \
            --no-headers 2>/dev/null | awk '{print $3}' | head -1)
        echo "  ceph-csi-controller-manager not ready — waiting 10s... (${csi_op_elapsed}s/300s) [pod: ${pod_status:-not found}]"
    fi
    sleep 10
    (( csi_op_elapsed += 10 )) || true
done
if (( csi_op_elapsed >= 300 )); then
    echo "ERROR: ceph-csi-controller-manager did not become ready within 300s."
    echo "  Deployment:"
    $KUBECTL get deployment -n rook-ceph ceph-csi-controller-manager -o wide 2>/dev/null || true
    echo "  Pod status:"
    $KUBECTL get pods -n rook-ceph -l "control-plane=ceph-csi-op-controller-manager" -o wide 2>/dev/null || true
    echo "  Pod logs:"
    $KUBECTL logs -n rook-ceph deployment/ceph-csi-controller-manager --tail=50 2>/dev/null || true
    exit 1
fi

# ── Wait for Rook to create CephConnection/OperatorConfig CRs (precondition for CSI provisioner) ──
echo "Waiting for CephConnection/OperatorConfig CRs from Rook (up to 300s)..."
cr_elapsed=0
while (( cr_elapsed < 300 )); do
    conn=$($KUBECTL get cephconnection -n rook-ceph --no-headers 2>/dev/null | wc -l || echo 0)
    opcfg=$($KUBECTL get operatorconfig -n rook-ceph --no-headers 2>/dev/null | wc -l || echo 0)
    if (( conn > 0 && opcfg > 0 )); then
        echo "  CephConnection (${conn}) and OperatorConfig (${opcfg}) found (${cr_elapsed}s)"
        break
    fi
    if (( cr_elapsed % 30 == 0 )); then
        echo "  CephConnection=${conn} OperatorConfig=${opcfg} — waiting 10s... (${cr_elapsed}s/300s)"
    fi
    sleep 10
    (( cr_elapsed += 10 )) || true
done
if (( cr_elapsed >= 300 )); then
    echo "ERROR: Rook did not create CephConnection/OperatorConfig CRs within 300s."
    echo "  Rook operator logs (last 50 lines):"
    $KUBECTL logs -n rook-ceph deployment/rook-ceph-operator --tail=50 2>/dev/null || true
    echo "  ceph-csi-controller-manager logs (last 50 lines):"
    $KUBECTL logs -n rook-ceph deployment/ceph-csi-controller-manager --tail=50 2>/dev/null || true
    exit 1
fi

echo "Waiting for CSI provisioner pods (up to 900s)..."
# ceph-csi-operator names ctrlplugin deployments after the CephConnection:
# <cephconnection-name>.<driver>.csi.ceph.com-ctrlplugin
# CephConnection is named "rook-ceph", so deployments are:
#   rook-ceph.rbd.csi.ceph.com-ctrlplugin
#   rook-ceph.cephfs.csi.ceph.com-ctrlplugin
for csi_deploy in \
    "rook-ceph.rbd.csi.ceph.com-ctrlplugin" \
    "rook-ceph.cephfs.csi.ceph.com-ctrlplugin"; do
    csi_elapsed=0
    while (( csi_elapsed < 900 )); do
        avail=$($KUBECTL get deployment -n rook-ceph "$csi_deploy" \
            -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)
        if [[ "$avail" =~ ^[1-9] ]]; then
            echo "  $csi_deploy: $avail available replicas (${csi_elapsed}s)"
            break
        fi
        if (( csi_elapsed % 60 == 0 )); then
            desired=$($KUBECTL get deployment -n rook-ceph "$csi_deploy" \
                -o jsonpath='{.status.replicas}/{.status.readyReplicas}/{.status.availableReplicas}' 2>/dev/null || echo "not found")
            echo "  $csi_deploy not ready — waiting 15s... (${csi_elapsed}s/900s) [desired/ready/avail: ${desired}]"
        else
            echo "  $csi_deploy not ready — waiting 15s... (${csi_elapsed}s/900s)"
        fi
        sleep 15
        (( csi_elapsed += 15 )) || true
    done
    if (( csi_elapsed >= 900 )); then
        echo "ERROR: $csi_deploy did not become ready within 900s."
        echo "  Deployment status:"
        $KUBECTL get deployment -n rook-ceph "$csi_deploy" -o wide 2>/dev/null || true
        echo "  Pods:"
        $KUBECTL get pods -n rook-ceph -l "app.kubernetes.io/name=$csi_deploy" -o wide 2>/dev/null || true
        echo "  ceph-csi-controller-manager logs:"
        $KUBECTL logs -n rook-ceph deployment/ceph-csi-controller-manager --tail=80 2>/dev/null || true
        echo "  Ceph cluster health:"
        $KUBECTL -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.ceph}' 2>/dev/null || true
        exit 1
    fi
done
echo "Rook-Ceph is fully operational — PVC provisioning available."
mark_step_done "rook-ceph-cluster"
# rook-ceph-storageclass is applied above; mark done so the old separate step is skipped
mark_step_done "rook-ceph-storageclass"
fi

if ! is_step_done "rook-ceph-storageclass"; then
echo "Next step defined the storage classes"
$KUBECTL apply -f $config_source_dir/infrastructure/rook-ceph/storageclass.yaml
mark_step_done "rook-ceph-storageclass"
fi

# install a tz manager and set the local timezone to UTC
if ! is_step_done "k8tz"; then
helm repo add k8tz https://k8tz.github.io/k8tz/
helm repo update

helm upgrade --install k8tz k8tz/k8tz \
    --set timezone=Europe/London \
    --set "injection.namespaceSelector.matchExpressions[0].key=kubernetes.io/metadata.name" \
    --set "injection.namespaceSelector.matchExpressions[0].operator=NotIn" \
    --set "injection.namespaceSelector.matchExpressions[0].values[0]=k8tz"
mark_step_done "k8tz"
fi

if ! is_step_done "namespaces"; then
# The 'olm' namespace was removed along with the OLM and quay steps — see the
# note where the OLM install used to be, below. 'operators' is left in place: the
# name is generic enough that something outside this repo may use it, and an
# empty namespace costs nothing.
$KUBECTL get namespace operators >/dev/null 2>&1 || $KUBECTL create namespace operators
$KUBECTL label --overwrite namespace operators  pod-security.kubernetes.io/audit=privileged  pod-security.kubernetes.io/warn=privileged pod-security.kubernetes.io/enforce=privileged
mark_step_done "namespaces"
fi

echo "install 'purelb' deployment"
if ! is_step_done "purelb"; then
helm repo add purelb https://gitlab.com/api/v4/projects/20400619/packages/helm/stable
helm repo update

$KUBECTL get namespace purelb >/dev/null 2>&1 || $KUBECTL create namespace purelb
$KUBECTL label --overwrite namespace purelb  pod-security.kubernetes.io/audit=privileged  pod-security.kubernetes.io/warn=privileged pod-security.kubernetes.io/enforce=privileged

helm upgrade --install  --namespace=purelb purelb purelb/purelb


echo "waiting for the 'purelb' deployment"
WaitForDeploymentToComplete purelb allocator 15
mark_step_done "purelb"
fi
 
if ! is_step_done "purelb-config"; then
echo "create the 'purelb' service group and ingress class"
$KUBECTL apply -f - <<EOF
apiVersion: purelb.io/v1
kind: ServiceGroup
metadata:
  name: default
  namespace: purelb
spec:
  local:
    v4pools:
    - subnet: ${LB_POOL_SUBNET}
      pool: ${LB_POOL_RANGE}
      aggregation: default
EOF
mark_step_done "purelb-config"
fi

# ── REMOVED: Operator Lifecycle Manager (OLM) ────────────────────────────────
# OLM was installed here solely to serve two Subscriptions, both of which are
# gone:
#   1. cert-manager — installed a SECOND cert-manager from operatorhubio on top
#      of the static v1.19.2 bundle applied a few steps below. Two installs
#      contending for the same CRDs and webhooks; the static bundle is
#      self-sufficient and is what the cluster actually runs.
#   2. quay — the project-quay operator, for an in-cluster Quay registry that
#      was never adopted. The registry in use is deployed by
#      infrastructure/registry/install.sh into the container-registry namespace.
#
# It was also broken: quay.io/operator-framework/olm is absent from the
# bootstrap registry, so 'kubectl apply -f vendor/olm.yaml' could only ever
# produce ImagePullBackOff.
#
# infrastructure/vendor/olm.yaml and olm-crds.yaml are retained on disk but are
# no longer applied by anything, and are no longer rendered by
# scripts/render-manifests.sh. If OLM is ever reinstated, mirror the olm image
# into the registry first and add olm.yaml back to that script's MANIFESTS list.

if ! is_step_done "cert-manager"; then
echo "install the cert-manager"

echo "create cert-manager namespace"
$KUBECTL get namespace cert-manager >/dev/null 2>&1 || $KUBECTL create namespace cert-manager
$KUBECTL label --overwrite namespace cert-manager  pod-security.kubernetes.io/audit=privileged  pod-security.kubernetes.io/warn=privileged pod-security.kubernetes.io/enforce=privileged
 
$KUBECTL apply -f "$config_source_dir/infrastructure/vendor/cert-manager-v1.19.2.yaml"

# NOTE: an OLM OperatorGroup + Subscription used to follow this apply, installing
# a second cert-manager from operatorhubio on top of the static bundle above.
# Removed with OLM — the static v1.19.2 bundle installs the controller,
# cainjector, webhook and all cert-manager CRDs on its own. Two installs fighting
# over the same CRDs and webhook configurations was never the intent.
#
# The bundle's image references are rewritten to the current registry by
# scripts/render-manifests.sh, which runs at the top of this script. Before that
# was wired up the bundle still pointed at the dead 10.0.0.1:5000, which is what
# made cert-manager silently absent and broke the Pulsar install downstream with
# 'no matches for kind "Certificate" in version "cert-manager.io/v1"'.

echo ""
echo "Check the cert-manager operator pods"
WaitForPodsRunning "cert-manager" "cert-manager" 35
echo "Check the cert-manager operator deploy"
WaitForDeploymentToComplete "cert-manager" "cert-manager-cainjector|cert-manager-webhook" 25
echo "Check the cert-manager service deploy"
WaitForServiceToStart "cert-manager" "cert-manager" 25
echo "Check the cert-manager-webhook service deploy"
WaitForServiceToStart "cert-manager" "cert-manager-webhook" 35
mark_step_done "cert-manager"


echo ""
# Wait for cert-manager webhook to be ready before requesting test cert.
echo "Waiting for cert-manager webhook to be Ready before creating test cert..."
$KUBECTL wait --for=condition=Ready pods \
    -l app.kubernetes.io/component=webhook \
    -n cert-manager \
    --timeout=300s \
    --request-timeout=20s 2>/dev/null || \
  echo "WARNING: cert-manager webhook pods not yet Ready — proceeding anyway"

echo ""
echo "test cert-manager deploy. this should create a self-signed certificate without error. see: cert-manager/test-resources.yaml"
$KUBECTL apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager-test
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: test-selfsigned
  namespace: cert-manager-test
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: selfsigned-cert
  namespace: cert-manager-test
spec:
  dnsNames:
    - example.com
  secretName: selfsigned-cert-tls
  issuerRef:
    name: test-selfsigned
EOF

echo ""
echo "Waiting for test cert to be Ready (timeout: 120s)..."
$KUBECTL wait --for=condition=Ready certificate/selfsigned-cert \
    -n cert-manager-test \
    --timeout=120s \
    --request-timeout=20s 2>/dev/null || true

echo "checking cert.  review this and ensure it looks like a valid cert"
$KUBECTL describe certificate -n cert-manager-test
### TODO Check the describe for 'validity'
echo ""

echo "delete cert-manager test components"
$KUBECTL delete -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager-test
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: test-selfsigned
  namespace: cert-manager-test
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: selfsigned-cert
  namespace: cert-manager-test
spec:
  dnsNames:
    - example.com
  secretName: selfsigned-cert-tls
  issuerRef:
    name: test-selfsigned
EOF

echo "waiting for cert-manager test namespace termination..."
$KUBECTL wait --for=delete namespace/cert-manager-test \
    --timeout=120s \
    --request-timeout=20s 2>/dev/null || true
fi

if ! is_step_done "local-registry"; then
echo "--- Bootstrapping Local Registry ---"
bash $config_source_dir/infrastructure/registry/install.sh
mark_step_done "local-registry"
fi

# ── REMOVED: Quay operator ───────────────────────────────────────────────────
# The project-quay OLM Subscription installed a Quay registry into a 'registry'
# namespace that was never adopted — the registry this cluster actually uses is
# deployed by infrastructure/registry/install.sh (above) into container-registry
# and reached at ${REGISTRY_LB_IP}. The 'registry' namespace does not exist on
# the cluster.
#
# Removed together with OLM, which was its only remaining consumer.
#
# Three unguarded diagnostics also lived here — 'kubectl get sub|csv|deployment
# -n registry'. They sat OUTSIDE the is_step_done guard, so with 'set -e' (line 5)
# they would abort this entire script once the OLM CRDs were gone: 'kubectl get
# sub' exits non-zero with "the server doesn't have a resource type sub". Every
# step below here — metrics-server, kube-state-metrics, traefik — would never run.

if ! is_step_done "metrics-server"; then
echo "installing the metrics API"
bash "$config_source_dir/infrastructure/metrics-server/metrics-server.sh"
mark_step_done "metrics-server"
fi

if ! is_step_done "kube-state-metrics"; then
echo "installing kube-state-metrics"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics \
  --namespace kube-system \
  --set selfMonitor.enabled=true
mark_step_done "kube-state-metrics"
fi

# the following depends on t KREW being installed along with the rook-ceph plugin

if ! is_step_done "krew"; then
echo "Installing KREW..."
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)
mark_step_done "krew"
fi

# Add krew to PATH for the rest of this script
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

if ! is_step_done "rook-ceph-plugin"; then
echo "Installing rook-ceph plugin via KREW..."
$KUBECTL krew install rook-ceph

$KUBECTL rook-ceph -n rook-ceph ceph config set class:hdd bdev_enable_discard false
$KUBECTL rook-ceph -n rook-ceph ceph config set class:hdd bluestore_slow_ops_warn_lifetime 60
$KUBECTL rook-ceph -n rook-ceph ceph config set class:hdd bluestore_slow_ops_warn_threshold 10
mark_step_done "rook-ceph-plugin"
fi


if ! is_step_done "krew kube ai"; then
echo "Installing kube ai plugin via KREW..."
$KUBECTL krew install ai

$KUBECTL rook-ceph -n rook-ceph ceph config set class:hdd bdev_enable_discard false
$KUBECTL rook-ceph -n rook-ceph ceph config set class:hdd bluestore_slow_ops_warn_lifetime 60
$KUBECTL rook-ceph -n rook-ceph ceph config set class:hdd bluestore_slow_ops_warn_threshold 10
mark_step_done "krew kube ai"
fi



if ! is_step_done "traefik"; then
echo "installing traefik"
source $config_source_dir/infrastructure/traefik/traefik.sh
mark_step_done "traefik"
fi

clear_journal
