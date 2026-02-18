#!/bin/bash
## setup-complete.sh - Master Orchestration Script
## To be executed on host: hierophant
#
set -e
#
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export BASE_DIR

source "$BASE_DIR/scripts/journal-helper.sh"
init_journal

#echo "===================================================="
#echo "Starting Complete Kubernetes Build and RAG Stack"
#echo "===================================================="
#
#echo ""
#echo "Step 1: Basic Infrastructure Setup"
#echo "----------------------------------------------------"
#$BASE_DIR/setup-01-basic.sh
#
#echo "SLEEPING FOR 30 minutes while rook-ceph comes up"
#echo "30 mins"
#sleep 600
#echo "20 mins"
#sleep 600
#echo "10 mins"
#sleep 600
#echo "DONE"

echo ""
echo "Step 1.4: NVIDIA Infrastructure Setup"
echo "----------------------------------------------------"
# Deploy NVIDIA device plugin and runtime class
bash $BASE_DIR/infrastructure/nvidia-operator.sh

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
