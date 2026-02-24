#!/bin/bash
## setup-complete.sh - Master Orchestration Script
## To be executed on host: hierophant
## Usage: FRESH_INSTALL=true [FORCE_REINIT=true] [REPO_DIR=<path>] ./setup-complete.sh
## Purpose: 
#     End-to-end bootstrap: 
#       basic infra (Rook-Ceph/Traefik), 
#       APM (LGTM+Alloy), 
#       NVIDIA stack, 
#       local registry, 
#       build+push RAG images, 
#       deploy RAG stack; 
#       resumable via scripts/journal-helper.sh.
## Config (optional): 
# FRESH_INSTALL=true -> clean from-scratch where supported; 
# FORCE_REINIT=true -> force Pulsar BookKeeper rejoin; 
# REPO_DIR -> override RAG stack path; 
# set NO_PROXY to include cluster CIDRs and .hierocracy.home; 
# child scripts default to KUBECTL=/home/k8s/kube/kubectl and KUBECONFIG=/home/k8s/kube/config/kubeconfig.
#

set -e
#
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export BASE_DIR

source "$BASE_DIR/scripts/journal-helper.sh"
init_journal

echo "===================================================="
echo "Starting Complete Kubernetes Build and RAG Stack"
echo "===================================================="

#if ! is_step_done "basic"; then
#echo ""
#echo "Step 1: Basic Infrastructure Setup (includes Rook-Ceph)"
#echo "----------------------------------------------------"
#$BASE_DIR/setup-01-basic.sh
#mark_step_done "basic"
#fi

if ! is_step_done "apm"; then
echo ""
echo "Step 1.2: APM (LGTM + Grafana Alloy)"
echo "----------------------------------------------------"
bash $BASE_DIR/infrastructure/APM/install.sh
mark_step_done "apm"
fi

if ! is_step_done "nvidia"; then
echo ""
echo "Step 1.4: NVIDIA Infrastructure Setup"
echo "----------------------------------------------------"
# Deploy NVIDIA device plugin and runtime class
bash $BASE_DIR/infrastructure/nvidia-operator.sh
mark_step_done "nvidia"
fi

if ! is_step_done "registry"; then
echo ""
echo "Step 1.5: Local Registry Setup"
echo "----------------------------------------------------"
$BASE_DIR/infrastructure/registry/install.sh
mark_step_done "registry"
fi

if ! is_step_done "rag-images"; then
echo ""
echo "Step 1.6: Build and Push RAG Images"
echo "----------------------------------------------------"
# Ensure we build the latest images and push them to our new local registry
$BASE_DIR/rag-stack/build-and-push.sh
mark_step_done "rag-images"
fi

if ! is_step_done "rag-stack"; then
echo ""
echo "Step 2: RAG Stack Deployment"
echo "----------------------------------------------------"
# We can either call setup-all.sh or we can un-comment the infra parts in it if needed.
# Since setup-01-basic.sh already handles Rook/Traefik, we only need the RAG services.

# Ensure REPO_DIR is set for the RAG stack
export REPO_DIR="$BASE_DIR/rag-stack"
$REPO_DIR/setup-all.sh
mark_step_done "rag-stack"
fi

clear_journal

echo ""
echo "===================================================="
echo "Complete Build Finished Successfully"
echo "===================================================="
