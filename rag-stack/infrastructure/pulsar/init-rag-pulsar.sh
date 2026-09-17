#!/bin/bash
# init-rag-pulsar.sh - Provision Pulsar tenants and namespaces for the RAG stack
# Run on hierophant

set -Eeuo pipefail

NAMESPACE="apache-pulsar"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
WAIT_SECONDS="${PULSAR_TOOL_POD_WAIT_SECONDS:-600}"
POLL_SECONDS=10

find_pulsar_admin_pod() {
    local pod=""
    local selectors=(
        "component=toolset"
        "app.kubernetes.io/component=toolset"
        "component=broker"
        "app.kubernetes.io/component=broker"
    )
    local sel
    for sel in "${selectors[@]}"; do
        pod=$($KUBECTL get pods -n "$NAMESPACE" -l "$sel" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
        if [[ -n "$pod" ]]; then
            echo "$pod"
            return 0
        fi
    done

    pod=$($KUBECTL get pods -n "$NAMESPACE" -o name 2>/dev/null | grep -E 'toolset|broker' | head -n1 | cut -d/ -f2 || true)
    if [[ -n "$pod" ]]; then
        echo "$pod"
        return 0
    fi

    return 1
}

echo "--- 1. Locating Pulsar Toolset Pod ---"
# Wait for a pod that can run pulsar-admin (prefer toolset, fallback broker)
echo "Waiting for Pulsar admin-capable pod in $NAMESPACE (timeout=${WAIT_SECONDS}s)..."
TOOLSET_POD=""
elapsed=0
while [[ "$elapsed" -lt "$WAIT_SECONDS" ]]; do
    TOOLSET_POD="$(find_pulsar_admin_pod || true)"
    if [[ -n "$TOOLSET_POD" ]]; then
        break
    fi
    echo "Pulsar admin pod not found yet. Sleeping ${POLL_SECONDS}s..."
    sleep "$POLL_SECONDS"
    elapsed=$((elapsed + POLL_SECONDS))
done

if [[ -z "$TOOLSET_POD" ]]; then
    echo "ERROR: Could not find a toolset/broker pod in namespace $NAMESPACE after ${WAIT_SECONDS}s"
    echo "Current Pulsar pods:"
    $KUBECTL get pods -n "$NAMESPACE" -o wide || true
    echo "Recent events:"
    $KUBECTL get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -n 60 || true
    exit 1
fi

echo "Using Pulsar admin pod: $TOOLSET_POD"
$KUBECTL wait --for=condition=Ready "pod/$TOOLSET_POD" -n "$NAMESPACE" --timeout=300s

pulsar_admin() {
    $KUBECTL exec -n "$NAMESPACE" "$TOOLSET_POD" -- /pulsar/bin/pulsar-admin "$@"
}

# WHY THESE LOOK CLUMSIER THAN "cmd | grep -q" (fixed 2026-09-17)
#
# This script runs under `set -Eeuo pipefail`. `grep -q` exits the instant it
# matches and closes the pipe; the `kubectl exec` producer then hits EPIPE and
# exits non-zero, and pipefail makes the PIPELINE report that failure -- even
# though grep matched. So `if ! cmd | grep -q X` could take the "missing"
# branch for something that plainly exists, try to create it, get HTTP 409, and
# abort the whole install on `set -e`.
#
# It is a race, so it looked arbitrary. Exposure depends on match position,
# because the listings are alphabetical: an early match short-circuits while
# the producer is still writing, a late one does not. Observed 2026-09-17 on
# rag-pipeline/dlq (2nd of 6) while stage (6th) and operations (4th) passed in
# the same run, and pulsar-init then succeeded on retry with no code change.
#
# Two defences, both needed:
#   1. capture the listing into a variable first, so grep cannot signal the
#      producer at all (and, for namespaces, fetch it ONCE instead of per-item);
#   2. treat "already exists" from a create as success -- it is idempotent, and
#      no amount of pre-checking removes the create/check window.
#
# Do NOT "simplify" these back into `cmd | grep -q`.

# Succeeded-or-empty: a listing failure must not masquerade as "not found",
# so callers check the create result too.
pulsar_list() { pulsar_admin "$@" 2>/dev/null || true; }

# Run a create, tolerating an "already exists" collision.
pulsar_create_idempotent() {
    local what="$1"; shift
    local out rc=0
    out="$(pulsar_admin "$@" 2>&1)" || rc=$?
    if [[ $rc -ne 0 ]]; then
        if printf '%s\n' "$out" | grep -qiE 'already exist'; then
            echo "  $what already existed (409 tolerated)"
            return 0
        fi
        printf '%s\n' "$out" >&2
        return $rc
    fi
    return 0
}

echo "--- 2. Ensuring 'rag-pipeline' tenant exists ---"
existing_tenants="$(pulsar_list tenants list)"
if ! printf '%s\n' "$existing_tenants" | grep -q "^rag-pipeline$"; then
    pulsar_create_idempotent "tenant rag-pipeline" tenants create rag-pipeline
    echo "Created tenant: rag-pipeline"
else
    echo "Tenant 'rag-pipeline' already exists"
fi

echo "--- 3. Ensuring namespaces exist ---"
namespaces=("stage" "data" "operations" "dlq" "sessions" "embed")
# Fetched once: six execs become one, and there is no per-item pipeline to race.
existing_ns="$(pulsar_list namespaces list rag-pipeline)"
for ns in "${namespaces[@]}"; do
    full_ns="rag-pipeline/$ns"
    if ! printf '%s\n' "$existing_ns" | grep -q "^$full_ns$"; then
        pulsar_create_idempotent "namespace $full_ns" namespaces create "$full_ns"
        echo "Created namespace: $full_ns"
        # Enable topic auto-creation if it was disabled
        pulsar_admin namespaces set-is-allow-auto-update-schema "$full_ns" --enable
    else
        echo "Namespace '$full_ns' already exists"
    fi

    # Specialized policies for sessions namespace
    if [[ "$ns" == "sessions" ]]; then
        echo "Applying specialized policies for $full_ns"
        # Set message TTL to 30 minutes (1800 seconds)
        pulsar_admin namespaces set-message-ttl "$full_ns" --messageTTL 1800 || true
        # Set inactive topic policy to delete after 5 minutes of inactivity (300 seconds)
        pulsar_admin namespaces set-inactive-topic-policies "$full_ns" \
            --enable-delete-while-inactive \
            --max-inactive-duration 300s \
            --delete-mode delete_when_no_subscriptions || true
    fi

    # Specialized policies for embed namespace:
    #   - Short TTL (300s) — stale embed jobs and result messages are discarded quickly
    #   - Auto-create non-partitioned topics for per-worker result topics
    #   - Retention capped at 500 MB to prevent disk bloat from result churn
    #   - Inactive topic cleanup after 10 min — per-worker result topics that linger are removed
    if [[ "$ns" == "embed" ]]; then
        echo "Applying specialized policies for $full_ns"
        pulsar_admin namespaces set-message-ttl "$full_ns" --messageTTL 300 || true
        pulsar_admin namespaces set-retention "$full_ns" \
            --size 500M --time 10m || true
        pulsar_admin namespaces set-auto-topic-creation "$full_ns" \
            --enable --type non-partitioned || true
        pulsar_admin namespaces set-inactive-topic-policies "$full_ns" \
            --enable-delete-while-inactive \
            --max-inactive-duration 600s \
            --delete-mode delete_when_no_subscriptions || true
    fi
done

echo "--- 4. Creating partitioned embed/jobs topic ---"
EMBED_JOBS_TOPIC="persistent://rag-pipeline/embed/jobs"
topic_meta="$(pulsar_list topics get-partitioned-topic-metadata "$EMBED_JOBS_TOPIC")"
if printf '%s\n' "$topic_meta" | grep -q '"partitions"'; then
    echo "Topic $EMBED_JOBS_TOPIC already exists"
else
    # 8 partitions — one per worker-node embed pod pair, allows parallel consumption
    pulsar_create_idempotent "topic $EMBED_JOBS_TOPIC" \
        topics create-partitioned-topic "$EMBED_JOBS_TOPIC" --partitions 8
    echo "Created partitioned topic: $EMBED_JOBS_TOPIC (8 partitions)"
fi

echo "Pulsar initialization for RAG stack complete."
