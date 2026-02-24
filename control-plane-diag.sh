#!/usr/bin/env bash
# k8s-controlplane-diagnose.sh — Collect control-plane stability diagnostics
# To be executed on host: hierophant

# Safety: keep going even if some commands fail; avoid hangs via timeouts
set -o pipefail

KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
# Ensure proxies do not interfere with cluster traffic
export HTTP_PROXY="" HTTPS_PROXY="" http_proxy="" https_proxy=""
export NO_PROXY="127.0.0.1,localhost,10.0.0.0/8,10.96.0.0/12,.cluster.local,.hierocracy.home,10.0.0.15"
export no_proxy="$NO_PROXY"

TS=$(date +%Y%m%d-%H%M%S)
OUT="./controlplane_diag_${TS}.txt"

echo "[INFO] Writing diagnostics to: $OUT"

section() {
  echo -e "\n===== $1 =====\n" | tee -a "$OUT"
}

run() {
  echo -e "\n$ $*\n" | tee -a "$OUT"
  # shellcheck disable=SC2068
  ( $@ ) >> "$OUT" 2>&1 || echo "[WARN] Command failed: $*" >> "$OUT"
}

# 0) Basic environment
section "Environment"
run date
run hostnamectl
run uname -a
# Older kubectl on hierophant doesn't support --short; print full version instead
run "$KUBECTL" version
run env | egrep -i 'KUBECONFIG|HTTP_PROXY|HTTPS_PROXY|NO_PROXY|http_proxy|https_proxy|no_proxy'

# 1) Sample API readiness (15 samples over ~30s)
section "API /readyz?verbose sampling (15x)"
for i in $(seq 1 15); do
  echo "--- sample $i ---" | tee -a "$OUT"
  run "$KUBECTL" --request-timeout=5s get --raw /readyz?verbose
  sleep 2
done

# 2) kube-system core pods and recent events
section "kube-system core pods"
run "$KUBECTL" -n kube-system get pods -o wide --show-labels --request-timeout=10s
section "kube-system recent events (last 200 lines)"
run bash -lc "$KUBECTL -n kube-system get events --sort-by=.lastTimestamp | tail -n 200"

# 3) kube-apiserver details
APISERVER_POD=$($KUBECTL -n kube-system get pods -l component=kube-apiserver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "$APISERVER_POD" ]]; then
  section "kube-apiserver describe (first 200 lines)"
  run bash -lc "$KUBECTL -n kube-system describe pod $APISERVER_POD | sed -n '1,200p'"
  section "kube-apiserver logs (last 200 lines)"
  run "$KUBECTL" -n kube-system logs "$APISERVER_POD" --tail=200
else
  echo "[WARN] kube-apiserver pod not found via label component=kube-apiserver" | tee -a "$OUT"
fi

# 4) kube-vip (if present)
section "kube-vip pods"
run "$KUBECTL" -n kube-system get pods -l app.kubernetes.io/name=kube-vip -o wide
KV_POD=$($KUBECTL -n kube-system get pods -l app.kubernetes.io/name=kube-vip -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "$KV_POD" ]]; then
  section "kube-vip logs (last 300 lines)"
  run "$KUBECTL" -n kube-system logs "$KV_POD" --tail=300
fi

# 5) etcd health, status, alarms, and memory/quota details
ETCD_POD=$($KUBECTL -n kube-system get pods -l component=etcd -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "$ETCD_POD" ]]; then
  section "etcd pod: $ETCD_POD — endpoint health/status/alarms"
  run "$KUBECTL" -n kube-system exec "$ETCD_POD" -- sh -lc '
    ETCDCTL_API=3 etcdctl \
      --endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key endpoint health || true
    ETCDCTL_API=3 etcdctl \
      --endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key endpoint status --write-out=table || true
    ETCDCTL_API=3 etcdctl \
      --endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key alarm list || true'
  section "etcd process memory (VmSize/VmRSS) and env/cmdline"
  run "$KUBECTL" -n kube-system exec "$ETCD_POD" -- sh -lc 'egrep "^(Name|VmSize|VmRSS):" /proc/1/status; echo; echo "[environ]"; tr "\0" "\n" < /proc/1/environ | egrep -i "ETCD|QUOTA|QUOTA_BACKEND|QUOTA_BACKEND_BYTES" || true; echo; echo "[cmdline]"; tr "\0" " " < /proc/1/cmdline || true'
  section "etcd backend store sizes (db/wal)"
  run "$KUBECTL" -n kube-system exec "$ETCD_POD" -- sh -lc 'du -h /var/lib/etcd/member/snap/db 2>/dev/null || true; du -sh /var/lib/etcd/member/* 2>/dev/null || true; ls -lh /var/lib/etcd/member/snap 2>/dev/null || true; ls -lh /var/lib/etcd/member/wal | tail -n 10 2>/dev/null || true'
  section "etcd pod YAML (first 200 lines: look for --quota-backend-bytes)"
  run bash -lc "$KUBECTL -n kube-system get pod $ETCD_POD -o yaml | sed -n '1,200p'"
else
  echo "[WARN] etcd pod not found via label component=etcd" | tee -a "$OUT"
fi

# 6) Control-plane node resource checks (SSH into each)
section "Control-plane nodes resource snapshot"
CP_NODES=$($KUBECTL get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
echo "Nodes: $CP_NODES" | tee -a "$OUT"
for n in $CP_NODES; do
  ip=$($KUBECTL get node "$n" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
  section "Node $n ($ip) — resource snapshot"
  run bash -lc "ssh -o BatchMode=yes -o ConnectTimeout=5 junie@$ip 'set -o pipefail; echo [timedatectl]; timedatectl 2>/dev/null | sed -n 1,6p; echo; echo [uptime]; uptime; echo; echo [df -h roots]; df -h / /var/lib/etcd /var/lib/kubelet 2>/dev/null || df -h; echo; echo [free -m]; free -m; echo; echo [conntrack]; sysctl -n net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max 2>/dev/null || true; echo; echo [dmesg tail]; dmesg -T | tail -n 50; echo; echo [kubelet logs 10m]; journalctl -u kubelet --since "10 min ago" --no-pager | tail -n 200'"
done

# 7) VIP reachability and TLS handshake
section "VIP 10.0.0.15 reachability"
run ping -c3 -W1 10.0.0.15
section "VIP TLS handshake (openssl s_client first 40 lines)"
run bash -lc "timeout 5 openssl s_client -connect 10.0.0.15:6443 -servername kubernetes < /dev/null 2>&1 | sed -n '1,40p'"

# 8) Summary pointer
section "Completed"
echo "Diagnostics complete. File: $OUT" | tee -a "$OUT"

echo "[DONE] $OUT"
