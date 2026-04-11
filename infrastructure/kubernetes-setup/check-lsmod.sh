#!/bin/bash
export KUBECONFIG=/home/k8s/kube/config/kubeconfig
KUBECTL=/home/k8s/kube/kubectl

$KUBECTL delete job check-lsmod -n rook-ceph --ignore-not-found

cat <<EOF | $KUBECTL apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: check-lsmod
  namespace: rook-ceph
spec:
  template:
    spec:
      hostPID: true
      containers:
      - name: check-lsmod
        image: docker.io/library/busybox:latest
        securityContext:
          privileged: true
        command: ["lsmod"]
      restartPolicy: Never
  backoffLimit: 0
EOF
