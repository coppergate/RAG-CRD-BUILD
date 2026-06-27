
export BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export KUBECTL="/home/k8s/kube/kubectl"

set -e

# this should point to the location of the directory
# which houses some script functions that help with the k8s builds
export config_source_dir="$BASE_DIR"
source "$config_source_dir/scripts/k8s-install-helper-functions.sh"
source "$config_source_dir/scripts/journal-helper.sh"

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
# REQUIRES to start MONs — without them the cluster controller fails every reconcile.
# We apply the CRDs+RBAC but immediately scale the ceph-csi-controller-manager
# Deployment to 0 replicas so the crash-looping controller doesn't hammer the API server.
$KUBECTL apply -f $config_source_dir/infrastructure/rook-ceph/csi-operator.yaml
$KUBECTL scale deployment -n rook-ceph ceph-csi-controller-manager --replicas=0 2>/dev/null || true
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

echo "Waiting for CSI provisioner pods (up to 900s)..."
for csi_deploy in \
    "rook-ceph.rbd.csi.ceph.com-ctrlplugin" \
    "rook-ceph.cephfs.csi.ceph.com-ctrlplugin"; do
    csi_elapsed=0
    while (( csi_elapsed < 900 )); do
        running=$($KUBECTL get pods -n rook-ceph \
            -l "app=${csi_deploy}" \
            --field-selector=status.phase=Running --no-headers 2>/dev/null | grep -c . || echo 0)
        if (( running > 0 )); then
            echo "  $csi_deploy: $running Running pods (${csi_elapsed}s)"
            break
        fi
        # Also accept if the deployment exists and has available replicas
        avail=$($KUBECTL get deployment -n rook-ceph "$csi_deploy" \
            -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)
        if [[ "$avail" =~ ^[1-9] ]]; then
            echo "  $csi_deploy: $avail available replicas (${csi_elapsed}s)"
            break
        fi
        echo "  $csi_deploy not ready — waiting 15s... (${csi_elapsed}s/900s)"
        sleep 15
        (( csi_elapsed += 15 )) || true
    done
    if (( csi_elapsed >= 900 )); then
        echo "ERROR: $csi_deploy did not become ready within 900s."
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
$KUBECTL get namespace olm >/dev/null 2>&1 || $KUBECTL create namespace olm
$KUBECTL label --overwrite namespace olm  pod-security.kubernetes.io/audit=privileged  pod-security.kubernetes.io/warn=privileged pod-security.kubernetes.io/enforce=privileged

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
    - subnet: 172.20.0.0/16
      pool: 172.20.1.16-172.20.1.240
      aggregation: default
EOF
mark_step_done "purelb-config"
fi

if ! is_step_done "olm"; then
echo "installing crds"
$KUBECTL apply -f \
$config_source_dir/infrastructure/vendor/olm-crds.yaml

echo "waiting for OLM CRDs to be established..."
for crd in \
  operatorgroups.operators.coreos.com \
  clusterserviceversions.operators.coreos.com \
  catalogsources.operators.coreos.com \
  subscriptions.operators.coreos.com \
  installplans.operators.coreos.com; do
  $KUBECTL wait --for condition=established --timeout=60s "crd/$crd" 2>/dev/null || true
done

echo "installing olm"
$KUBECTL apply -f \
$config_source_dir/infrastructure/vendor/olm.yaml

# WaitForDeploymentToComplete namespace grepString sleepTime
WaitForDeploymentToComplete olm olm-operator 15
WaitForDeploymentToComplete olm catalog-operator 15
WaitForDeploymentToComplete olm packageserver 15
mark_step_done "olm"
fi

if ! is_step_done "cert-manager"; then
echo "install the cert-manager"

echo "create cert-manager namespace"
$KUBECTL get namespace cert-manager >/dev/null 2>&1 || $KUBECTL create namespace cert-manager
$KUBECTL label --overwrite namespace cert-manager  pod-security.kubernetes.io/audit=privileged  pod-security.kubernetes.io/warn=privileged pod-security.kubernetes.io/enforce=privileged
 
$KUBECTL apply -f "$config_source_dir/infrastructure/vendor/cert-manager-v1.19.2.yaml"

$KUBECTL apply -f - <<EOF
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: og-cert-manager
  namespace: cert-manager
spec:
  targetNamespaces:
  - cert-manager
---
apiVersion: operators.coreos.com/v1alpha1 
kind: Subscription 
metadata: 
  name: cert-manager-local 
  namespace: cert-manager
spec: 
  channel: stable 
  name: cert-manager 
  source: operatorhubio-catalog 
  sourceNamespace: olm
EOF

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
# for some reason this next step fails if it happens too soon after the deploy?
echo "Waiting for 120s to let the cert-manager catch its breath before we ask for the test cert"
sleep 120;

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
echo "Waiting for 25s to let the cert-manager make the test cert available"
sleep 25

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

echo "waiting for 1 minute"

sleep 1m;
fi

if ! is_step_done "local-registry"; then
echo "--- Bootstrapping Local Registry ---"
bash $config_source_dir/infrastructure/registry/install.sh
mark_step_done "local-registry"
fi

#setup an operator group in the registry namespace
#then add the 'quay' operator (container registry service) subscription

echo "apply the quay operator"

if ! is_step_done "quay"; then
$KUBECTL get namespace registry >/dev/null 2>&1 || $KUBECTL create namespace registry
$KUBECTL label --overwrite namespace registry  pod-security.kubernetes.io/audit=privileged  pod-security.kubernetes.io/warn=privileged pod-security.kubernetes.io/enforce=privileged

$KUBECTL apply -f - <<EOF
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: og-single
  namespace: registry
spec:
  targetNamespaces:
  - registry
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: quay
  namespace: registry
spec:
  channel: stable-3.8
  installPlanApproval: Automatic
  name: project-quay
  source: operatorhubio-catalog
  sourceNamespace: olm
  startingCSV: quay-operator.v3.8.1

EOF

WaitForDeploymentToComplete registry quay-operator 15
mark_step_done "quay"
fi
# $KUBECTL expose deployment quay --name=quay-server --port=8080 --target-port=8080 --type=LoadBalancer -n registry

echo "check the 'quay' subscription"
$KUBECTL get sub -n registry

echo "the 'quay' cluster service version"
$KUBECTL get csv -n registry

echo "the 'quay' deployment"
$KUBECTL get deployment -n registry

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
