#!/usr/bin/env bash
# fix-registry-pvc-stuck.sh
# Clears a stuck RBD CSI mount for the container-registry PVC.
# Run directly on hierophant.
set -euo pipefail

export KUBECONFIG=/home/k8s/kube/config/kubeconfig
KUBECTL=/home/k8s/kube/kubectl
NAMESPACE=container-registry
DEPLOYMENT=registry
PV_NAME=pvc-72418faf-a6ff-4cbe-a4f5-f7211fad850b
RBD_POOL=ceph-replica-pool
RBD_IMAGE=csi-vol-179a6b96-2503-405d-af05-76dd0c0be03d
TARGET_NODE=worker-0

# Use rook-ceph-mgr pod for ceph/rbd commands (no separate toolbox in this cluster)
TOOLBOX_POD=$($KUBECTL get pod -n rook-ceph -l app=rook-ceph-mgr \
  -o jsonpath='{.items[0].metadata.name}')
CSI_RBD_LABEL="app=rook-ceph.rbd.csi.ceph.com-nodeplugin"

echo "=== Step 1: Scale registry deployment to 0 and confirm pod is GONE ==="
$KUBECTL scale deployment -n $NAMESPACE $DEPLOYMENT --replicas=0
echo "  Waiting for all registry pods to fully terminate..."
# Hard wait — do not proceed until there are zero pods, no stragglers
until [[ $($KUBECTL get pod -n $NAMESPACE -l app=registry --no-headers 2>/dev/null | wc -l) -eq 0 ]]; do
  echo "  Still terminating..."
  sleep 3
done
echo "  All registry pods gone."

echo ""
echo "=== Step 2: Blocklist any stale RBD watcher ==="
WATCHERS=$($KUBECTL exec -n rook-ceph "$TOOLBOX_POD" -c mgr -- \
  rbd status $RBD_POOL/$RBD_IMAGE 2>/dev/null | grep 'watcher=' || true)

if [[ -n "$WATCHERS" ]]; then
  echo "  Found watchers:"
  echo "$WATCHERS"
  while IFS= read -r line; do
    CLIENT_ADDR=$(echo "$line" | grep -oP 'watcher=\K[^ ]+')
    if [[ -n "$CLIENT_ADDR" ]]; then
      echo "  Blocklisting: $CLIENT_ADDR"
      $KUBECTL exec -n rook-ceph "$TOOLBOX_POD" -c mgr -- \
        ceph osd blocklist add "$CLIENT_ADDR" || true
    fi
  done <<< "$WATCHERS"
else
  echo "  No watchers found — skipping blocklist."
fi

echo ""
echo "=== Step 3: Delete stale VolumeAttachment ==="
VA=$($KUBECTL get volumeattachment \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.source.persistentVolumeName}{"\n"}{end}' \
  | grep "$PV_NAME" | awk '{print $1}' || true)

if [[ -n "$VA" ]]; then
  echo "  Deleting VolumeAttachment: $VA"
  $KUBECTL delete volumeattachment "$VA"
  echo "  Waiting for VolumeAttachment to be gone..."
  until ! $KUBECTL get volumeattachment "$VA" &>/dev/null; do
    sleep 2
  done
  echo "  VolumeAttachment gone."
else
  echo "  No VolumeAttachment found for this PV — skipping."
fi

echo ""
echo "=== Step 4: Restart CSI RBD node plugin on $TARGET_NODE ==="
CSI_POD=$($KUBECTL get pod -n rook-ceph \
  -l "$CSI_RBD_LABEL" \
  --field-selector spec.nodeName=$TARGET_NODE \
  -o jsonpath='{.items[0].metadata.name}')
echo "  Deleting pod: $CSI_POD"
$KUBECTL delete pod -n rook-ceph "$CSI_POD" --grace-period=0 --force

echo "  Waiting for new CSI node plugin pod to appear..."
until [[ $($KUBECTL get pod -n rook-ceph \
  -l "$CSI_RBD_LABEL" \
  --field-selector spec.nodeName=$TARGET_NODE \
  --no-headers 2>/dev/null | wc -l) -gt 0 ]]; do
  sleep 2
done
echo "  Waiting for CSI node plugin to be Ready..."
$KUBECTL wait pod -n rook-ceph \
  -l "$CSI_RBD_LABEL" \
  --field-selector spec.nodeName=$TARGET_NODE \
  --for=condition=Ready --timeout=120s
echo "  CSI plugin ready."

echo "  Pausing 5s to let the driver fully register with kubelet..."
sleep 5

echo ""
echo "=== Step 5: Scale registry deployment back to 1 ==="
$KUBECTL scale deployment -n $NAMESPACE $DEPLOYMENT --replicas=1

echo ""
echo "=== Step 6: Watch for registry pod to come up ==="
echo "  (Ctrl+C to exit once Running)"
$KUBECTL get pod -n $NAMESPACE -w
