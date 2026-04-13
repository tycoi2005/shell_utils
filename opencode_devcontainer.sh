#!/usr/bin/env zsh
# setup-opencode-devcontainer.sh
# Adds opencode to a devcontainer.json (creates one if missing),
# mounts auth.json / model.json / opencode.json, and rebuilds if anything changed.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
OPENCODE_FEATURE="ghcr.io/danzilberdan/devcontainers/opencode:0"
OPENCODE_SHARE="${HOME}/.local/share/opencode"
OPENCODE_CONFIG="${HOME}/.config/opencode"

# Container user — "root" keeps things simple (matches opencode-docker).
# The devcontainer base image defaults to "vscode" (home=/home/vscode),
# but opencode inside the feature runs as whatever remoteUser is set to.
CONTAINER_USER="root"

AUTH_SRC="${OPENCODE_SHARE}/auth.json"
MODEL_SRC="${HOME}/.local/state/opencode/model.json"
RUNTIME_CONFIG_SRC="${OPENCODE_CONFIG}/config.json"

DEVCONTAINER_DIR=".devcontainer"
DEVCONTAINER_FILE="${DEVCONTAINER_DIR}/devcontainer.json"

GIT_NAME="tycoi2005"
GIT_EMAIL="tycoi2005@opencode"

for arg in "$@"; do
  case "$arg" in
    --git-name=*)       GIT_NAME="${arg#--git-name=}" ;;
    --git-email=*)      GIT_EMAIL="${arg#--git-email=}" ;;
    --container-user=*) CONTAINER_USER="${arg#--container-user=}" ;;
  esac
done

# Compute container home from user
if [[ "$CONTAINER_USER" == "root" ]]; then
  CONTAINER_HOME="/root"
else
  CONTAINER_HOME="/home/${CONTAINER_USER}"
fi

# Mount directly to their final destinations for two-way sync (OAuth persistence)
AUTH_TARGET="${CONTAINER_HOME}/.local/share/opencode/auth.json"
MODEL_TARGET="${CONTAINER_HOME}/.local/state/opencode/model.json"
CONFIG_TARGET="${CONTAINER_HOME}/.config/opencode/opencode.json"
RUNTIME_CONFIG_TARGET="${CONTAINER_HOME}/.config/opencode/config.json"

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { print -P "%F{cyan}[info]%f  $*" }
success() { print -P "%F{green}[ok]%f    $*" }
warn()    { print -P "%F{yellow}[warn]%f  $*" }
error()   { print -P "%F{red}[error]%f $*" >&2; exit 1 }

require() {
  command -v "$1" &>/dev/null || error "'$1' is required but not installed."
}

# ── Dependency check ──────────────────────────────────────────────────────────
require jq
require docker

# Ensure Docker daemon is reachable before invoking devcontainer commands.
if ! docker info >/dev/null 2>&1; then
  error "Docker is installed but the daemon is not reachable. Start Docker Desktop (or your Docker engine) and retry."
fi

# ── 2. Initialize .devcontainer/devcontainer.json if missing/invalid ──────────
if [[ ! -f "$DEVCONTAINER_FILE" || ! -s "$DEVCONTAINER_FILE" ]] || ! jq -e . "$DEVCONTAINER_FILE" &>/dev/null; then
  info "devcontainer.json missing or invalid — initializing with default."
  mkdir -p "$DEVCONTAINER_DIR"
  printf '{\n  "name": "Dev Container",\n  "image": "mcr.microsoft.com/devcontainers/python:3",\n  "remoteUser": "%s",\n  "features": {},\n  "mounts": []\n}\n' "$CONTAINER_USER" > "$DEVCONTAINER_FILE"
fi

ORIGINAL=$(cat "$DEVCONTAINER_FILE")
UPDATED="$ORIGINAL"

# ── 3. Add image if missing ───────────────────────────────────────────────────
HAS_IMAGE=$(printf '%s\n' "$UPDATED" | jq 'if .image or .dockerFile or .dockerComposeFile then true else false end')
if [[ "$HAS_IMAGE" == "false" ]]; then
  info "No image specified — adding default Python image..."
    UPDATED=$(printf '%s\n' "$UPDATED" | jq -c '.image = "mcr.microsoft.com/devcontainers/python:3"')
  success "Added image: mcr.microsoft.com/devcontainers/python:3"
else
  info "Image already specified, skipping."
fi

# ── 4. Add opencode feature if missing ────────────────────────────────────────
HAS_FEATURE=$(printf '%s\n' "$UPDATED" | jq --arg f "$OPENCODE_FEATURE" \
  'if .features | has($f) then true else false end')
if [[ "$HAS_FEATURE" == "false" ]]; then
  info "Adding opencode feature..."
  UPDATED=$(printf '%s\n' "$UPDATED" | jq -c --arg f "$OPENCODE_FEATURE" '.features[$f] = {}')
  success "Added feature: ${OPENCODE_FEATURE}"
else
  info "opencode feature already present, skipping."
fi

# ── 4a. Add github-cli feature if missing ─────────────────────────────────────
# Use the stable major tag so the feature can resolve reliably.
GH_FEATURE="ghcr.io/devcontainers/features/github-cli:1"
HAS_GH_FEATURE=$(printf '%s\n' "$UPDATED" | jq --arg f "$GH_FEATURE" \
  'if .features | has($f) then true else false end')
if [[ "$HAS_GH_FEATURE" == "false" ]]; then
  info "Adding github-cli feature..."
  UPDATED=$(printf '%s\n' "$UPDATED" | jq -c --arg f "$GH_FEATURE" '.features[$f] = {}')
  success "Added feature: ${GH_FEATURE}"
else
  info "github-cli feature already present, skipping."
fi

# ── 4b. Add node feature if missing ───────────────────────────────────────────
NODE_FEATURE="ghcr.io/devcontainers/features/node:1"
HAS_NODE_FEATURE=$(printf '%s\n' "$UPDATED" | jq --arg f "$NODE_FEATURE" \
  'if .features | has($f) then true else false end')
if [[ "$HAS_NODE_FEATURE" == "false" ]]; then
  info "Adding node feature..."
  UPDATED=$(printf '%s\n' "$UPDATED" | jq -c --arg f "$NODE_FEATURE" '.features[$f] = {}')
  success "Added feature: ${NODE_FEATURE}"
else
  info "node feature already present, skipping."
fi

# ── 4c. Ensure remoteUser is set correctly ────────────────────────────────────
CURRENT_USER=$(printf '%s\n' "$UPDATED" | jq -r '.remoteUser // empty')
if [[ "$CURRENT_USER" != "$CONTAINER_USER" ]]; then
  info "Setting remoteUser to '${CONTAINER_USER}'..."
  UPDATED=$(printf '%s\n' "$UPDATED" | jq -c --arg u "$CONTAINER_USER" '.remoteUser = $u')
  success "remoteUser set to '${CONTAINER_USER}'"
else
  info "remoteUser already set to '${CONTAINER_USER}', skipping."
fi

# ── 5. Ensure correct mounts (remove stale, add missing) ─────────────────────
ensure_mount() {
  local src="$1" target="$2" label="$3"

  if [[ ! -f "$src" ]]; then
    warn "${label} not found at ${src} — skipping."
    return
  fi

  local mount_str="source=${src},target=${target},type=bind,consistency=cached"

  # Check if exact correct mount already exists
  local has_exact
  has_exact=$(printf '%s\n' "$UPDATED" | jq --arg m "$mount_str" \
    'if .mounts then (.mounts | map(select(. == $m)) | length > 0) else false end')

  if [[ "$has_exact" == "true" ]]; then
    info "${label} mount already correct, skipping."
    return
  fi

  # Remove any existing mount touching this target's path fragments, then add correct one
  info "Updating mount for ${label}..."
  UPDATED=$(printf '%s\n' "$UPDATED" | jq -c \
    --arg target "$target" \
    --arg src "$src" '
    .mounts = (
      [.mounts[]? | select(type == "string" and (contains($target) | not))]
      + ["source=\($src),target=\($target),type=bind,consistency=cached"]
    )')
  success "Mounted ${src} → ${target}"
}

ensure_mount "$AUTH_SRC"           "$AUTH_TARGET"           "auth.json"
ensure_mount "$MODEL_SRC"          "$MODEL_TARGET"          "model.json"
ensure_mount "$RUNTIME_CONFIG_SRC" "$RUNTIME_CONFIG_TARGET" "config.json"

# Delete any existing opencode.json mounts as we generate it dynamically
UPDATED=$(printf '%s\n' "$UPDATED" | jq -c '
  .mounts = [
    .mounts[]? |
    select(
      type == "string" and (
        contains("opencode/opencode.json") | not
      )
    )
  ]')

# Inject postCreateCommand to generate opencode.json and install pytest
info "Configuring inline opencode.json and dev tools..."
COMMAND='mkdir -p ~/.config/opencode && cat > ~/.config/opencode/opencode.json << '"'"'EOF'"'"'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": "allow",
  "plugin": [
    "@nguquen/opencode-anthropic-auth@0.0.14",
    "opencode-vibeguard"
  ]
}
EOF
pip install pytest'

UPDATED=$(printf '%s\n' "$UPDATED" | jq -c --arg cmd "$COMMAND" '.postCreateCommand = $cmd')

# ── 6. Write back only if changed ─────────────────────────────────────────────
# Normalize both for comparison (jq sorts keys consistently)
ORIGINAL_NORM=$(printf '%s\n' "$ORIGINAL" | jq -Sc .)
UPDATED_NORM=$(printf '%s\n' "$UPDATED" | jq -Sc .)

if [[ "$UPDATED_NORM" == "$ORIGINAL_NORM" ]]; then
  success "devcontainer.json already up-to-date — nothing to write."
  CHANGED=false
else
  printf '%s\n' "$UPDATED" | jq '.' > "$DEVCONTAINER_FILE"
  success "devcontainer.json updated."
  CHANGED=true
fi

# ── 7. Ensure devcontainer CLI is available ───────────────────────────────────
if ! command -v devcontainer &>/dev/null; then
  error "devcontainer CLI not found. Install it with: npm install -g @devcontainers/cli"
fi

# ── 8. Stop any existing container for this workspace so mounts are re-applied ─
EXISTING=$(docker ps -q --filter "label=devcontainer.local_folder=$(pwd)" 2>/dev/null || true)
if [[ -n "$EXISTING" ]]; then
  if [[ "$CHANGED" == "true" ]]; then
    info "Stopping existing container so new config takes effect..."
    docker stop "$EXISTING" &>/dev/null
    docker rm "$EXISTING" &>/dev/null || true
  fi
fi

# ── 9. Rebuild image if config changed ────────────────────────────────────────
if [[ "$CHANGED" == "true" ]]; then
  info "Changes detected — rebuilding container (this may take a moment)..."
  devcontainer build --workspace-folder . || error "Build failed."
  success "Container rebuilt."
else
  info "No config changes — starting container as-is..."
fi

# ── 10. Bring container up ────────────────────────────────────────────────────
info "Bringing container up..."
UP_OUTPUT=$(devcontainer up --workspace-folder . 2>&1) || error "Failed to start container:\n${UP_OUTPUT}"

CONTAINER_ID=$(echo "$UP_OUTPUT" | grep -o '"containerId":"[^"]*"' | tail -1 | cut -d'"' -f4)

if [[ -z "$CONTAINER_ID" ]]; then
  warn "Could not detect container ID — will skip auto-stop on exit."
else
  success "Container running: ${CONTAINER_ID:0:12}"
fi

# ── 11. Configure git identity inside the container ───────────────────────────
if [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]]; then
  info "Setting git identity inside container..."
  devcontainer exec --workspace-folder . git config --global user.name "$GIT_NAME"
  devcontainer exec --workspace-folder . git config --global user.email "$GIT_EMAIL"
  success "Git identity set: $GIT_NAME <$GIT_EMAIL>"
fi

# ── 12. Ensure GitHub CLI is available in-container ───────────────────────────
info "Checking for GitHub CLI (gh) inside container..."
if devcontainer exec --workspace-folder . sh -lc 'command -v gh >/dev/null 2>&1'; then
  success "GitHub CLI is available."
else
  warn "GitHub CLI not found — attempting to install in container..."
  devcontainer exec --workspace-folder . sh -lc '
    set -e
    if command -v apt-get >/dev/null 2>&1; then
      if command -v sudo >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y gh
      elif [ "$(id -u)" -eq 0 ]; then
        apt-get update
        apt-get install -y gh
      else
        echo "Cannot auto-install gh: need sudo or root in container." >&2
        exit 1
      fi
    else
      echo "Cannot auto-install gh: apt-get is unavailable in this container image." >&2
      exit 1
    fi
  ' || error "Failed to install GitHub CLI (gh) in container."

  devcontainer exec --workspace-folder . sh -lc 'command -v gh >/dev/null 2>&1' \
    || error "GitHub CLI (gh) is still unavailable after install attempt."
  success "GitHub CLI installed and verified."
fi

info "GitHub CLI version inside container:"
devcontainer exec --workspace-folder . gh --version || error "Failed to run gh --version inside container."

# ── 13. Run opencode inside the container ─────────────────────────────────────
info "Launching opencode inside the container..."
print ""
devcontainer exec --workspace-folder . opencode || true

# ── 14. Stop container when opencode exits ────────────────────────────────────
if [[ -n "$CONTAINER_ID" ]]; then
  info "opencode exited — stopping container ${CONTAINER_ID:0:12}..."
  docker stop "$CONTAINER_ID" &>/dev/null && success "Container stopped." || warn "Could not stop container — may already be stopped."
else
  warn "opencode exited — stop the container manually with: docker ps"
fi
