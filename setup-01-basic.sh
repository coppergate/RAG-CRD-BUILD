
export BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export KUBECTL="/home/k8s/kube/kubectl"

# this should point to the location of the directory
# which houses some script functions that help with the k8s builds
export config_source_dir="$BASE_DIR"
source "$config_source_dir/scripts/k8s-install-helper-functions.sh"
source "$config_source_dir/scripts/journal-helper.sh"

init_journal

#fresh k8s cluster
 
# ip r add 10.2.0.0/24 via 172.16.64.32
# nmcli conn 

# to develop operators apply the following 
#./olm.setup.sh

#echo "create a local olm sdk install..."
#operator-sdk olm install --timeout 5m0s

if ! is_step_done "labels"; then
$KUBECTL label nodes worker-0 role=storage-node
$KUBECTL label nodes worker-1 role=storage-node
$KUBECTL label nodes worker-2 role=storage-node
$KUBECTL label nodes worker-3 role=storage-node

$KUBECTL label nodes inference-0 role=inference-node
$KUBECTL label nodes inference-1 role=inference-node
mark_step_done "labels"
fi

# install a tz manager and set the local timezone to UTC
if ! is_step_done "k8tz"; then
helm repo add k8tz https://k8tz.github.io/k8tz/
helm repo update

helm install k8tz k8tz/k8tz --set timezone=Europe/London
mark_step_done "k8tz"
fi

if ! is_step_done "namespaces"; then
$KUBECTL create namespace olm
$KUBECTL label --overwrite namespace olm  pod-security.kubernetes.io/audit=privileged  pod-security.kubernetes.io/warn=privileged pod-security.kubernetes.io/enforce=privileged

$KUBECTL create namespace operators
$KUBECTL label --overwrite namespace operators  pod-security.kubernetes.io/audit=privileged  pod-security.kubernetes.io/warn=privileged pod-security.kubernetes.io/enforce=privileged
mark_step_done "namespaces"
fi

if ! is_step_done "olm"; then
echo "installing crds"
$KUBECTL create -f \
$config_source_dir/infrastructure/vendor/olm-crds.yaml

echo "installing olm"
$KUBECTL create -f \
$config_source_dir/infrastructure/vendor/olm.yaml

# WaitForDeploymentToComplete namespace grepString sleepTime
WaitForDeploymentToComplete olm olm-operator 15
WaitForDeploymentToComplete olm catalog-operator 15
WaitForDeploymentToComplete olm packageserver 15
mark_step_done "olm"
fi

#setup an operator group in the registry namespace
#then add the 'quay' operator (container registry service) subscription

echo "apply the quay operator"

if ! is_step_done "quay"; then
$KUBECTL create namespace registry
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

echo "install 'purelb' deployment"
if ! is_step_done "purelb"; then
helm repo add purelb https://gitlab.com/api/v4/projects/20400619/packages/helm/stable
helm repo update

$KUBECTL create namespace purelb
$KUBECTL label --overwrite namespace purelb  pod-security.kubernetes.io/audit=privileged  pod-security.kubernetes.io/warn=privileged pod-security.kubernetes.io/enforce=privileged

helm install  --namespace=purelb purelb purelb/purelb


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

if ! is_step_done "cert-manager"; then
echo "install the cert-manager"

echo "create cert-manager namespace"
$KUBECTL create namespace cert-manager
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
fi

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

if ! is_step_done "metrics-server"; then
echo "installing the metrics API"
$KUBECTL apply -f "$config_source_dir/infrastructure/vendor/metrics-server-components.yaml"

echo "waiting for 1 minute"
sleep 1m;
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

if ! is_step_done "rook-ceph-image-prefetch"; then
echo "prefetching rook-ceph images to node-local cache (pre-registry bootstrap)"
bash $config_source_dir/scripts/prefetch-node-images.sh --group storage
mark_step_done "rook-ceph-image-prefetch"
fi

if ! is_step_done "rook-ceph-operator"; then
echo "install rook-ceph operator"

$KUBECTL create namespace rook-ceph

# wipe disks before cluster creation to ensure clean OSDs
if ! is_step_done "rook-ceph-wipe-disks"; then
  bash $config_source_dir/infrastructure/rook-ceph/wipe-disks.sh
  mark_step_done "rook-ceph-wipe-disks"
fi

# for the example crd:
# cd /mnt/hegemon-share/code/kubernetes-app-setup/app-builds/rook/
# git clone --single-branch --branch v1.16.5 https://github.com/rook/rook.git
# cd /mnt/hegemon-share/code/kubernetes-app-setup/app-builds/rook/rook/deploy/examples

helm repo add rook-release https://charts.rook.io/release

$KUBECTL create -f $config_source_dir/infrastructure/rook-ceph/crds.yaml 
$KUBECTL create -f $config_source_dir/infrastructure/rook-ceph/common.yaml 
$KUBECTL create -f $config_source_dir/infrastructure/rook-ceph/csi-operator.yaml 
$KUBECTL create -f $config_source_dir/infrastructure/rook-ceph/operator.yaml

$KUBECTL label --overwrite namespace rook-ceph  pod-security.kubernetes.io/audit=privileged  pod-security.kubernetes.io/warn=privileged pod-security.kubernetes.io/enforce=privileged

echo "Check the ceph-operator pod"
WaitForPodsRunning "rook-ceph" "rook-ceph-operator" 240
mark_step_done "rook-ceph-operator"
fi

if ! is_step_done "rook-ceph-cluster"; then
echo "Next step the storage CRDs"

$KUBECTL create -f $config_source_dir/infrastructure/rook-ceph/cluster.yaml
$KUBECTL create -f $config_source_dir/infrastructure/rook-ceph/filesystem.yaml
$KUBECTL create -f $config_source_dir/infrastructure/rook-ceph/object.yaml
$KUBECTL create -f $config_source_dir/infrastructure/rook-ceph/pool.yaml


echo "Check the ceph-rook-cephfs/rdb deploys"
sleep 300
$KUBECTL wait -n rook-ceph --for 'jsonpath={.status.conditions[?(@.type=="Ready")].status}=True' deployment.apps/rook-ceph.cephfs.csi.ceph.com-ctrlplugin --timeout=600s
$KUBECTL wait -n rook-ceph --for 'jsonpath={.status.conditions[?(@.type=="Ready")].status}=True' deployment.apps/rook-ceph.rbd.csi.ceph.com-ctrlplugin  --timeout=600s
mark_step_done "rook-ceph-cluster"
fi

if ! is_step_done "rook-ceph-storageclass"; then
echo "Next step defined the storage classes"
$KUBECTL create -f $config_source_dir/infrastructure/rook-ceph/storageclass.yaml
mark_step_done "rook-ceph-storageclass"
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

if ! is_step_done "traefik"; then
echo "installing traefik"
source $config_source_dir/infrastructure/traefik/traefik.sh
mark_step_done "traefik"
fi

clear_journal
