#!/bin/bash
# install-opencode.sh - OpenCode coding agent (https://opencode.ai) as an
#                       in-cluster service, pointed at the cluster's Ollama.
# To be executed on host: hierophant
#
# ── What this is, and what the upstream write-up got wrong ───────────────────
# OpenCode itself is a LOCAL tool (terminal / desktop / IDE extension, installed
# with `curl -fsSL https://opencode.ai/install | bash`). What runs in a cluster
# is a third-party wrapper chart, neomanexlabs/opencode, which hosts the agent
# as a StatefulSet exposing a web UI + HTTP API. Corrections against the notes
# this script was written from:
#
#   claimed                              actual
#   -----------------------------------  -----------------------------------
#   chart kubeopencode/kubeopencode      repo alias neomanexlabs, chart opencode
#   namespace kubeopencode-system        chart has no fixed ns; we use $NAMESPACE
#   service port 8080                    server.port = 4096
#   llm.provider/baseUrl/model keys      providers{} map + model "prov/model"
#   baseUrl http://cluster.local         not a resolvable address at all
#   ingressClassName nginx               this cluster runs Traefik
#   host opencode.local                  convention is *.hierocracy.home
#   model qwen2.5-coder                  not seeded here; see OPENCODE_MODEL
#
# Two further errors were only caught by `helm template` (step 5 below), which
# is why that step exists and must stay:
#   - providers/model/smallModel live under `config:`, not at top level;
#   - `workspaces` defaults to [] and the StatefulSet is `range .workspaces`,
#     so with no workspace the chart renders ONE object and silently installs
#     nothing that runs. A workspace is a git repo checkout, so it needs a repo
#     URL, a branch, a PVC size, and an SSH key secret for the clone.
#
# ── ⚠ CHART LIMITS IN THIS ENVIRONMENT (verified by reading the templates) ───
# This chart is built around GCP External Secrets Operator. With
# externalSecrets.enabled=false -- the only option here, there is no GCP -- BOTH
# of these mounts vanish (statefulset.yaml:283-291 and :304-313):
#
#   /etc/opencode/secrets   provider API-key files
#   /home/opencode/.ssh     SSH key for the workspace git clone
#
# Consequences, neither of which this script can work around:
#   1. A PRIVATE workspace repo cannot be cloned -- there is no key in the pod.
#      Use a public repo, or accept that the checkout fails.
#   2. configmap.yaml:113-117 renders apiKey as "{file:/etc/opencode/secrets/
#      <provider.secretKey>}" unconditionally. With secretKey unset it emits the
#      Go error string "%!s(<nil>)"; with it set, the file does not exist anyway.
#      Ollama ignores auth, so a bogus value is harmless in principle, but this
#      is unverified until something actually runs.
#
# Also: statefulset.yaml:40 hardcodes `image: alpine/git:latest` for the init
# container. Not overridable through values, BARE, and unpinned. Bare refs
# resolve through the containerd mirror, which strips the host and asks
# hierophant for /v2/alpine/git/manifests/latest -- so step 1b mirrors it to
# exactly that path. It will still drift, because upstream controls :latest.
#
# Given all of the above, and that OpenCode is primarily a LOCAL tool, running
# it on the dev VM against the Ollama LoadBalancer is the lower-friction option.
# See the closing notes.
#
# ── Why NO ingress by default ────────────────────────────────────────────────
# The chart only injects OPENCODE_SERVER_PASSWORD when externalSecrets.enabled
# is true (statefulset.yaml:164), and that path is GCP Secret Manager only. With
# external secrets off, server.passwordAuth has nothing to enforce, so the API
# is UNAUTHENTICATED. This agent executes code and holds cluster credentials, so
# it is kept on a ClusterIP and reached through `kubectl port-forward`, which at
# least requires kubeconfig. Set OPENCODE_EXPOSE=ingress only if you have
# fronted it with auth yourself -- and note the DNS reminder printed at the end,
# because the *.hierocracy.home wildcard was removed (OPERATIONS.md 1.7).
set -Eeuo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$REPO_DIR/../.." && pwd)
KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"

# Single source of truth for network + registry addressing (flat-LAN design).
# shellcheck source=../../config/network.env
source "$BASE_DIR/config/network.env"
# shellcheck source=../../scripts/journal-helper.sh
source "$BASE_DIR/scripts/journal-helper.sh"
init_journal

NAMESPACE="${OPENCODE_NAMESPACE:-opencode}"
RELEASE="${OPENCODE_RELEASE:-opencode}"
CHART_REPO_NAME="neomanexlabs"
CHART_REPO_URL="https://neomanexlabs.github.io/helm-charts"
CHART="${CHART_REPO_NAME}/opencode"
CHART_VERSION="${OPENCODE_CHART_VERSION:-1.4.5}"

# Upstream image. This cluster is air-gapped by convention: every image must be
# mirrored into the bootstrap registry and referenced through REGISTRY_PREFIX,
# never bare (a bare ref resolves via the containerd mirror, which strips the
# host, 404s, and falls through to the internet -- OPERATIONS.md 1.7.2).
UPSTREAM_IMAGE="${OPENCODE_UPSTREAM_IMAGE:-ghcr.io/neomanexlabs/opencode}"
IMAGE_TAG="${OPENCODE_IMAGE_TAG:-1.14.48}"
LOCAL_IMAGE="${REGISTRY_PREFIX}/${UPSTREAM_IMAGE}"

# Ollama endpoint. 'ollama-code' is the service intended for coding work; it is
# backed by the ollama-qwen32b deployment, whose PVC holds every seeded GPU
# model, so any seeded model name is servable here. Ollama 0.15.6 exposes an
# OpenAI-compatible /v1 API, which is what @ai-sdk/openai-compatible expects.
OLLAMA_URL="${OPENCODE_OLLAMA_URL:-http://ollama-code.llms-ollama.svc.cluster.local:11434/v1}"
# Seeded GPU models: devstral-small-2:24b, qwen3:32b, qwen2.5:32b,
# granite3.1-dense:8b, llama3.1, llama3.2. devstral-small-2 is the documented
# coding executor for this stack (see values-devstral.yaml).
OPENCODE_MODEL="${OPENCODE_MODEL:-devstral-small-2:24b}"

# A workspace is a git checkout the agent works inside. The chart mounts
# externalSecrets.sshKey.secretName (default opencode-ssh-key) into the pod
# unconditionally, so that secret must exist for the clone to succeed.
WS_NAME="${OPENCODE_WORKSPACE_NAME:-rag-crd-build}"
WS_REPO="${OPENCODE_REPO:-git@github.com:coppergate/RAG-CRD-BUILD.git}"
WS_BRANCH="${OPENCODE_BRANCH:-main}"
WS_SIZE="${OPENCODE_WS_SIZE:-10Gi}"
SSH_SECRET="${OPENCODE_SSH_SECRET:-opencode-ssh-key}"
SSH_KEY_FILE="${OPENCODE_SSH_KEY_FILE:-$HOME/.ssh/id_hierophant_access}"

EXPOSE="${OPENCODE_EXPOSE:-portforward}"   # portforward | ingress
INGRESS_HOST="${OPENCODE_INGRESS_HOST:-opencode.hierocracy.home}"
VALUES_FILE="$REPO_DIR/values-generated.yaml"

echo "=== OpenCode install ==="
echo "  namespace : $NAMESPACE"
echo "  chart     : $CHART (version $CHART_VERSION)"
echo "  image     : ${LOCAL_IMAGE}:${IMAGE_TAG}"
echo "  ollama    : $OLLAMA_URL"
echo "  model     : $OPENCODE_MODEL"
echo "  workspace : $WS_NAME ($WS_REPO @ $WS_BRANCH, $WS_SIZE)"
echo "  expose    : $EXPOSE"

# ── 1. Mirror the image ──────────────────────────────────────────────────────
# Verify probes the registry, so a mirror that already happened is skipped even
# if the journal was cleared.
image_present() {
  curl -sk -o /dev/null -fsS --max-time 15 \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json' \
    "https://${REGISTRY_PREFIX}/v2/${UPSTREAM_IMAGE}/manifests/${IMAGE_TAG}"
}
if ! is_step_done "opencode-image-mirror" image_present; then
  echo "--- 1. Mirroring ${UPSTREAM_IMAGE}:${IMAGE_TAG} into ${REGISTRY_PREFIX} ---"
  command -v skopeo >/dev/null 2>&1 || { echo "ERROR: skopeo required on hierophant" >&2; exit 1; }
  skopeo copy --all --dest-tls-verify=false \
    "docker://${UPSTREAM_IMAGE}:${IMAGE_TAG}" \
    "docker://${REGISTRY_PREFIX}/${UPSTREAM_IMAGE}:${IMAGE_TAG}"
  mark_step_done "opencode-image-mirror"
else
  echo "--- 1. Image already mirrored ---"
fi

# ── 1b. Mirror the chart's hardcoded init-container image ────────────────────
# statefulset.yaml:40 uses a bare `alpine/git:latest`. Mirrored to the path the
# containerd host-stripping mirror will actually request.
git_image_present() {
  curl -sk -o /dev/null -fsS --max-time 15 \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json' \
    "https://${REGISTRY_PREFIX}/v2/alpine/git/manifests/latest"
}
if ! is_step_done "opencode-git-image-mirror" git_image_present; then
  echo "--- 1b. Mirroring alpine/git:latest (chart hardcodes it) ---"
  skopeo copy --all --dest-tls-verify=false \
    "docker://docker.io/alpine/git:latest" \
    "docker://${REGISTRY_PREFIX}/alpine/git:latest"
  mark_step_done "opencode-git-image-mirror"
else
  echo "--- 1b. alpine/git already mirrored ---"
fi

# ── 2. Namespace ─────────────────────────────────────────────────────────────
if ! is_step_done "opencode-namespace" "$KUBECTL" get namespace "$NAMESPACE"; then
  echo "--- 2. Creating namespace $NAMESPACE ---"
  $KUBECTL create namespace "$NAMESPACE"
  mark_step_done "opencode-namespace"
else
  echo "--- 2. Namespace exists ---"
fi

# ── 2b. SSH key secret for the workspace git clone ───────────────────────────
# NOTE: with externalSecrets.enabled=false the chart does NOT mount this secret
# (statefulset.yaml:304-313), so creating it does NOT enable private-repo
# clones. Created anyway so the wiring exists if ESO is ever introduced.
# Non-fatal by design: a missing key must not block the install.
if ! is_step_done "opencode-ssh-secret" "$KUBECTL" -n "$NAMESPACE" get secret "$SSH_SECRET"; then
  if [[ -f "$SSH_KEY_FILE" ]]; then
    echo "--- 2b. Creating secret/$SSH_SECRET from $SSH_KEY_FILE ---"
    $KUBECTL -n "$NAMESPACE" create secret generic "$SSH_SECRET" \
      --from-file=ssh-privatekey="$SSH_KEY_FILE"
    mark_step_done "opencode-ssh-secret"
  else
    echo "--- 2b. No SSH key at $SSH_KEY_FILE; skipping secret ---"
    echo "        Private-repo clones will fail regardless (see header)." >&2
  fi
else
  echo "--- 2b. SSH key secret exists ---"
fi

# ── 3. Helm repo (reaches the internet; the only step that does) ─────────────
echo "--- 3. Helm repo ---"
helm repo add "$CHART_REPO_NAME" "$CHART_REPO_URL" --force-update
helm repo update "$CHART_REPO_NAME"

# ── 4. Render values ─────────────────────────────────────────────────────────
echo "--- 4. Rendering $VALUES_FILE ---"
{
  cat <<VALUES
# GENERATED by install-opencode.sh -- edit the script, not this file.
image:
  repository: ${LOCAL_IMAGE}
  tag: "${IMAGE_TAG}"
  pullPolicy: IfNotPresent

server:
  port: 4096
  hostname: 0.0.0.0
  # No effect without externalSecrets (see header); recorded for intent.
  passwordAuth:
    enabled: false

externalSecrets:
  enabled: false
  sshKey:
    secretName: ${SSH_SECRET}

git:
  user:
    name: OpenCode
    email: opencode@hierocracy.home

# Each workspace is its own StatefulSet + PVC + ConfigMap. Without at least one,
# the chart renders nothing that runs.
workspaces:
  - name: ${WS_NAME}
    repo: ${WS_REPO}
    branch: ${WS_BRANCH}
    size: ${WS_SIZE}

# NOTE: providers/model are under config:, not top level.
config:
  # Ollama presented as an OpenAI-compatible provider. Ollama needs no key, but
  # the chart always renders one, so a placeholder is supplied deliberately.
  providers:
    ollama:
      npm: "@ai-sdk/openai-compatible"
      # No apiKey/secretKey: Ollama needs none, and the chart would render
      # "{file:/etc/opencode/secrets/<secretKey>}" against a path that is not
      # mounted unless externalSecrets is enabled. See header.
      options:
        baseURL: ${OLLAMA_URL}
      models:
        "${OPENCODE_MODEL}": {}
  model: "ollama/${OPENCODE_MODEL}"
  smallModel: ""
VALUES
  if [[ "$EXPOSE" == "ingress" ]]; then
    cat <<VALUES

ingress:
  enabled: true
  className: traefik
  host: ${INGRESS_HOST}
VALUES
  else
    cat <<VALUES

ingress:
  enabled: false
VALUES
  fi
} > "$VALUES_FILE"

# ── 5. Validate before touching the cluster ──────────────────────────────────
echo "--- 5. helm template (schema validation) ---"
helm template "$RELEASE" "$CHART" --version "$CHART_VERSION" \
  -n "$NAMESPACE" -f "$VALUES_FILE" > /tmp/opencode-rendered.yaml
echo "  rendered $(grep -c '^kind:' /tmp/opencode-rendered.yaml) objects"
grep -E '^\s+image:' /tmp/opencode-rendered.yaml | sort -u | sed 's/^/  /'

# ── 6. Install ───────────────────────────────────────────────────────────────
# Per-workspace StatefulSet is named "<release>-<workspace>".
opencode_ready() { $KUBECTL -n "$NAMESPACE" rollout status "statefulset/${RELEASE}-${WS_NAME}" --timeout=10s; }
if ! is_step_done "opencode-install" opencode_ready; then
  echo "--- 6. helm upgrade --install ---"
  helm upgrade --install "$RELEASE" "$CHART" --version "$CHART_VERSION" \
    -n "$NAMESPACE" -f "$VALUES_FILE" --wait --timeout 10m
  mark_step_done "opencode-install"
else
  echo "--- 6. Already installed and ready ---"
fi

# ── 7. Report ────────────────────────────────────────────────────────────────
echo
echo "=== Result ==="
$KUBECTL -n "$NAMESPACE" get statefulset,svc,pods 2>&1 | sed 's/^/  /'
SVC=$($KUBECTL -n "$NAMESPACE" get svc -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "$RELEASE")
echo
if [[ "$EXPOSE" == "ingress" ]]; then
  cat <<NOTE
Exposed via Traefik at http://${INGRESS_HOST}

  ⚠ UNAUTHENTICATED (see header). Front it with auth before relying on this.
  ⚠ DNS: the *.hierocracy.home wildcard was REMOVED (OPERATIONS.md 1.7), so the
    name will NOT resolve until you add it on diakonia:
        ${INGRESS_HOST%%.*}   CNAME   traefik.hierocracy.home.
NOTE
else
  cat <<NOTE
Reach it with a port-forward (requires kubeconfig, which is the access control):

    kubectl port-forward -n ${NAMESPACE} svc/${SVC} 4096:4096

Then point your editor / browser at  http://localhost:4096
(Leave the API key blank -- Ollama does not check one.)
NOTE
fi
cat <<NOTE

Model prerequisite: OpenCode is only useful once '${OPENCODE_MODEL}' is actually
loadable at ${OLLAMA_URL}. Model seeding happens in the rag-stack install step;
until that completes the endpoint answers nothing. Check with:

    kubectl -n llms-ollama run ocheck --rm -i --restart=Never \\
      --image=${REGISTRY_PREFIX}/curlimages/curl:7.78.0 --command -- \\
      curl -s ${OLLAMA_URL}/models
NOTE
echo "OpenCode installation complete."
