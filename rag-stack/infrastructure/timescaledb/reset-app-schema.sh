#!/usr/bin/env bash
# reset-app-schema.sh — Drop and recreate ONLY app-owned database objects
# Purpose: normalize ownership/privileges by recreating app tables/functions
# WARNING: This DELETES application data in the listed tables.
#
# Run on host: hierophant
# Non-interactive; uses pinned kubectl and kubeconfig per project guidelines

set -Eeuo pipefail

KB="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
REQ_TIMEOUT="20s"
DB_NAMESPACE="timescaledb"
SCHEMA_SQL="/mnt/hegemon-share/share/code/complete-build/rag-stack/infrastructure/timescaledb/schema.sql"

log() { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

[[ -x "$KB" ]] || fail "kubectl not found at $KB"
[[ -r "$KUBECONFIG" ]] || fail "kubeconfig not readable at $KUBECONFIG"
[[ -r "$SCHEMA_SQL" ]] || fail "schema.sql not found at $SCHEMA_SQL"

log "Locating TimescaleDB primary pod"
TS_POD=$($KB get pods -n "$DB_NAMESPACE" -l "cnpg.io/cluster=timescaledb,role=primary" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$TS_POD" ]]; then
  sleep 5
  TS_POD=$($KB get pods -n "$DB_NAMESPACE" -l "cnpg.io/cluster=timescaledb,role=primary" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi
[[ -n "$TS_POD" ]] || fail "TimescaleDB primary pod not found in namespace $DB_NAMESPACE"
log "Using DB pod: $TS_POD"

psql_pg() { # psql as postgres user
  $KB --request-timeout="$REQ_TIMEOUT" -n "$DB_NAMESPACE" exec -i "$TS_POD" -- psql -U postgres -d "$1" -v ON_ERROR_STOP=1 -c "$2"
}
psql_apply_as_app() { # apply given SQL file content as role app within a postgres session
  local file="$1"
  (
    echo "SET ROLE app;";
    cat "$file";
    printf '\nRESET ROLE;\n';
  ) | $KB --request-timeout="$REQ_TIMEOUT" -n "$DB_NAMESPACE" exec -i "$TS_POD" -- sh -lc "psql -U postgres -d app -v ON_ERROR_STOP=1"
}

log "Ensuring role 'app' exists and can create in schema public"
$KB -n "$DB_NAMESPACE" exec -i "$TS_POD" -- sh -lc \
  "psql -U postgres -d postgres -tc \"SELECT 1 FROM pg_roles WHERE rolname='app'\" | grep -q 1 || psql -U postgres -d postgres -c \"CREATE ROLE app LOGIN PASSWORD 'app'\""
psql_pg app "GRANT CONNECT ON DATABASE app TO app;"
psql_pg app "GRANT USAGE, CREATE ON SCHEMA public TO app;"

log "Removing Timescale job for expire_old_sessions if present"
psql_pg app "SELECT delete_job(job_id) FROM timescaledb_information.jobs WHERE proc_name = 'expire_old_sessions';" || true

log "Dropping mapping tables (session_tag, code_embedding_tag) if exist"
psql_pg app "DROP TABLE IF EXISTS session_tag, code_embedding_tag CASCADE;" || true

log "Dropping main app tables if exist (this deletes data)"
psql_pg app "DROP TABLE IF EXISTS responses, prompts, retrieval_logs, code_embedding, code_ingestion, tag, sessions, projects CASCADE;" || true

log "Dropping app procedure expire_old_sessions if exists"
psql_pg app "DROP PROCEDURE IF EXISTS expire_old_sessions(int, jsonb);" || true

log "Recreating unified schema as role 'app' (app will own all new objects)"
psql_apply_as_app "$SCHEMA_SQL"

log "Reset complete. Consider restarting DB-using services so they pick up fresh state."
log "Example: kubectl -n rag-system rollout restart deploy/db-adapter deploy/llm-gateway deploy/rag-worker"
