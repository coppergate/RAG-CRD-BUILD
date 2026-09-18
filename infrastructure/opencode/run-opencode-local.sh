#!/bin/bash
# run-opencode-local.sh - OpenCode in a LOCAL container, talking to the
#                         cluster's Ollama over the LAN.
#
# ⚠ THIS ONE RUNS ON THE DEV VM, NOT ON HIEROPHANT.
# That is deliberate and is the opposite of every other script here (see
# guidelines.md "Execution Environment"). OpenCode is a developer tool: it is
# used from the machine you edit on, and it only needs the cluster for
# inference. Nothing about it belongs in the cluster for this use case.
#
# WHY PREFER THIS OVER infrastructure/opencode/install-opencode.sh
# The in-cluster chart is built around GCP External Secrets. Without ESO it
# cannot mount an SSH key (so no private-repo checkout) and its server runs
# unauthenticated, and it hardcodes a bare unpinned alpine/git:latest init
# container. None of that applies here: the workspace is a bind mount of a
# checkout you already have, and the listener is bound to loopback.
#
# WHAT IT DOES
#   1. finds the Ollama endpoint (kubectl if reachable, else a known LB IP)
#   2. verifies the endpoint actually serves the model you asked for
#   3. writes an opencode.json pointing at it
#   4. runs the agent in a rootless container, workspace bind-mounted,
#      listening on 127.0.0.1 only
set -Eeuo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$REPO_DIR/../.." && pwd)
# shellcheck source=../../config/network.env
[[ -f "$BASE_DIR/config/network.env" ]] && source "$BASE_DIR/config/network.env"

# ── Config ───────────────────────────────────────────────────────────────────
NAME="${OPENCODE_CONTAINER_NAME:-opencode}"
PORT="${OPENCODE_PORT:-4096}"
# Bound to loopback on purpose: the agent executes code and has no auth.
BIND="${OPENCODE_BIND:-127.0.0.1}"
MODEL="${OPENCODE_MODEL:-devstral-small-2:24b}"
WORKSPACE="${OPENCODE_WORKSPACE:-$BASE_DIR}"
WS_NAME="${OPENCODE_WORKSPACE_NAME:-$(basename "$WORKSPACE")}"
STATE_DIR="${OPENCODE_STATE_DIR:-$HOME/.local/share/opencode-local}"
CONF_DIR="${OPENCODE_CONF_DIR:-$HOME/.config/opencode-local}"

# The chart's image, reused. Prefer the mirror; fall back upstream because this
# host has internet and is not the air-gapped surface the cluster is.
IMAGE_TAG="${OPENCODE_IMAGE_TAG:-1.14.48}"
UPSTREAM_IMAGE="ghcr.io/neomanexlabs/opencode:${IMAGE_TAG}"
MIRRORED_IMAGE="${REGISTRY_PREFIX:-hierophant.hierocracy.home:5000}/ghcr.io/neomanexlabs/opencode:${IMAGE_TAG}"

# ── Container runtime ────────────────────────────────────────────────────────
if command -v podman >/dev/null 2>&1; then
  RT=podman
  # keep-id maps this host uid to the same uid inside, so the bind-mounted
  # workspace stays writable and matches the image's uid-1000 user.
  RT_EXTRA=(--userns=keep-id)
elif command -v docker >/dev/null 2>&1; then
  RT=docker
  RT_EXTRA=(--user "$(id -u):$(id -g)")
else
  echo "ERROR: neither podman nor docker found on this machine." >&2
  exit 1
fi
echo "=== OpenCode (local container) ==="
echo "  runtime   : $RT"
echo "  workspace : $WORKSPACE  (as /workspace/$WS_NAME)"
echo "  listen    : ${BIND}:${PORT}"

# ── 1. Locate the Ollama endpoint ────────────────────────────────────────────
# 'ollama-code' is the coding endpoint (PureLB LoadBalancer). Discover its
# address rather than hardcoding, but fall back to the known IP when kubectl is
# not usable from here.
OLLAMA_URL="${OPENCODE_OLLAMA_URL:-}"
if [[ -z "$OLLAMA_URL" ]]; then
  ip=""
  if command -v kubectl >/dev/null 2>&1; then
    ip=$(kubectl --request-timeout=10s -n llms-ollama get svc ollama-code \
           -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  fi
  [[ -z "$ip" ]] && ip="${OPENCODE_OLLAMA_IP:-192.168.5.207}"
  OLLAMA_URL="http://${ip}:11434/v1"
fi
echo "  ollama    : $OLLAMA_URL"

# ── 2. Pre-flight: endpoint reachable AND serving the requested model ────────
# Worth checking explicitly: the models live on a PVC seeded during the
# rag-stack install, so the endpoint can be up while serving nothing.
echo "--- Pre-flight ---"
if ! models_json=$(curl -fsS --max-time 10 "${OLLAMA_URL}/models" 2>/dev/null); then
  echo "ERROR: $OLLAMA_URL is not answering." >&2
  echo "       Check the service:  kubectl -n llms-ollama get svc ollama-code" >&2
  exit 1
fi
if ! printf '%s' "$models_json" | grep -q -- "$MODEL"; then
  echo "ERROR: '$MODEL' is not served by $OLLAMA_URL." >&2
  echo "       Available:" >&2
  printf '%s' "$models_json" \
    | python3 -c 'import sys,json;[print("         -",m["id"]) for m in json.load(sys.stdin).get("data",[])]' 2>/dev/null \
    || printf '         %s\n' "$models_json" >&2
  echo "       Override with OPENCODE_MODEL=<id>." >&2
  exit 1
fi
echo "  endpoint OK, '$MODEL' available"

# ── 3. Write opencode.json ───────────────────────────────────────────────────
# Same shape the chart renders, minus the {file:} apiKey indirection: Ollama
# does not authenticate, so no key is configured at all.
mkdir -p "$CONF_DIR" "$STATE_DIR"
cat > "$CONF_DIR/opencode.json" <<JSON
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "ollama/${MODEL}",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (hierocracy cluster)",
      "options": { "baseURL": "${OLLAMA_URL}" },
      "models": { "${MODEL}": { "name": "${MODEL}" } }
    }
  }
}
JSON
echo "  wrote $CONF_DIR/opencode.json"

# ── 4. Image ─────────────────────────────────────────────────────────────────
IMAGE="$MIRRORED_IMAGE"
if ! $RT image exists "$IMAGE" 2>/dev/null; then
  echo "--- Pulling image ---"
  if ! $RT pull --tls-verify=false "$MIRRORED_IMAGE" 2>/dev/null; then
    echo "  mirror miss; pulling upstream $UPSTREAM_IMAGE"
    $RT pull "$UPSTREAM_IMAGE"
    IMAGE="$UPSTREAM_IMAGE"
  fi
fi
echo "  image: $IMAGE"

# ── 5. Run ───────────────────────────────────────────────────────────────────
# Idempotent: replace any previous instance.
$RT rm -f "$NAME" >/dev/null 2>&1 || true
echo "--- Starting $NAME ---"
# NO command override. The image ENTRYPOINT is already
#   opencode serve --port 4096 --hostname 0.0.0.0 --print-logs
# so anything passed here is appended as extra ARGS to `opencode serve`, which
# makes it print its help and exit. The container port is therefore always 4096
# regardless of $PORT; $PORT is only the host-side mapping.
#
# safe.directory is set through git's env-var config instead of a wrapper shell,
# so the entrypoint stays untouched. Needed because the workspace is a bind
# mount whose ownership git may consider dubious.
$RT run -d --name "$NAME" \
  "${RT_EXTRA[@]}" \
  -p "${BIND}:${PORT}:4096" \
  -v "$CONF_DIR/opencode.json:/home/opencode/.config/opencode/opencode.json:ro,Z" \
  -v "$WORKSPACE:/workspace/${WS_NAME}:rw,Z" \
  -v "$STATE_DIR:/home/opencode/.local/share/opencode:rw,Z" \
  -e HOME=/home/opencode \
  -e GIT_CONFIG_COUNT=1 \
  -e GIT_CONFIG_KEY_0=safe.directory \
  -e GIT_CONFIG_VALUE_0='*' \
  -w "/workspace/${WS_NAME}" \
  "$IMAGE" \
  >/dev/null

# ── 6. Verify it came up ─────────────────────────────────────────────────────
echo "--- Waiting for the server ---"
for i in $(seq 1 20); do
  if curl -fsS --max-time 3 "http://${BIND}:${PORT}/provider" >/dev/null 2>&1; then
    echo "  up after $((i*2))s"
    break
  fi
  if [[ "$($RT inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" != "true" ]]; then
    echo "ERROR: container exited. Logs:" >&2
    $RT logs "$NAME" 2>&1 | tail -n 25 >&2
    exit 1
  fi
  sleep 2
done

cat <<NOTE

=== Ready ===
  API / web UI : http://${BIND}:${PORT}
  Model        : ollama/${MODEL}  via ${OLLAMA_URL}
  Workspace    : ${WORKSPACE}

  JetBrains: point the OpenCode/AI plugin's server URL at http://${BIND}:${PORT}
             and leave the API key blank (Ollama does not check one).

  Logs :  ${RT} logs -f ${NAME}
  Stop :  ${RT} rm -f ${NAME}

  Bound to ${BIND} deliberately: this agent executes code and the server has no
  authentication. Do not publish it on 0.0.0.0 or behind an ingress.
NOTE
