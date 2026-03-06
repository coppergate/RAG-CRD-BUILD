#!/usr/bin/env bash
set -Eeuo pipefail

KB=/home/k8s/kube/kubectl; export KUBECONFIG=/home/k8s/kube/config/kubeconfig
TS_POD=$($KB get pods -n timescaledb -l 'cnpg.io/cluster=timescaledb,role=primary' -o jsonpath='{.items[0].metadata.name}')

if [[ -z "${TS_POD:-}" ]]; then
  echo "ERROR: TimescaleDB primary pod not found" >&2
  exit 1
fi

echo "[STEP] Ensure role 'app' exists"
$KB -n timescaledb exec -i "$TS_POD" -- \
  sh -lc "psql -U postgres -d postgres -tc \"SELECT 1 FROM pg_roles WHERE rolname='app'\" | grep -q 1 || psql -U postgres -d postgres -c \"CREATE ROLE app LOGIN PASSWORD 'app'\""

echo "[STEP] Set password for role 'app'"
$KB -n timescaledb exec -i "$TS_POD" -- \
  psql -U postgres -d postgres -c "ALTER ROLE app WITH LOGIN PASSWORD 'app'"

echo "[STEP] Ensure database 'app' exists and owned by app"
$KB -n timescaledb exec -i "$TS_POD" -- \
  sh -lc "psql -U postgres -d postgres -tc \"SELECT 1 FROM pg_database WHERE datname='app'\" | grep -q 1 || psql -U postgres -d postgres -c \"CREATE DATABASE app OWNER app\""

echo "[STEP] Apply secret and restart adapters"
$KB apply -f /mnt/hegemon-share/share/code/complete-build/rag-stack/infrastructure/timescaledb/timescaledb-secret.yaml
$KB -n rag-system rollout restart deploy/db-adapter deploy/llm-gateway deploy/rag-worker
$KB -n rag-system get pods -w
