#!/usr/bin/env zsh
# forge-devcontainer
# Adds ForgeCode to a devcontainer.json (creates one if missing),
# mounts credentials + config for auth persistence, and rebuilds if anything changed.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
CONTAINER_USER="root"

# ForgeCode stores everything under ~/forge/
# (credentials, config, DB, history, logs, snapshots)
FORGE_HOME="${HOME}/forge"

DEVCONTAINER_DIR=".devcontainer"
DEVCONTAINER_FILE="${DEVCONTAINER_DIR}/devcontainer.json"

GIT_NAME="tycoi2005"
GIT_EMAIL="tycoi2005@forgecode"

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

# Mount target inside the container (mirror host layout)
FORGE_TARGET="${CONTAINER_HOME}/forge"

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { print -P "%F{cyan}[info]%f  $*" }
success() { print -P "%F{green}[ok]%f    $*" }
warn()    { print -P "%F{yellow}[warn]%f  $*" }
die()     { print -P "%F{red}[error]%f $*" >&2; exit 1 }

require() {
  command -v "$1" &>/dev/null || die "'$1' is required but not installed."
}

# ── Dependency check ──────────────────────────────────────────────────────────
require jq
require docker

# ── Initialize .devcontainer/devcontainer.json if missing/invalid ─────────────
if [[ ! -f "$DEVCONTAINER_FILE" || ! -s "$DEVCONTAINER_FILE" ]] || ! jq -e . "$DEVCONTAINER_FILE" &>/dev/null; then
  info "devcontainer.json missing or invalid — initializing with default."
  mkdir -p "$DEVCONTAINER_DIR"
  printf '{\n  "name": "Dev Container",\n  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",\n  "remoteUser": "%s",\n  "features": {},\n  "mounts": []\n}\n' "$CONTAINER_USER" > "$DEVCONTAINER_FILE"
fi

ORIGINAL=$(cat "$DEVCONTAINER_FILE")
UPDATED="$ORIGINAL"

# ── Add image if missing ─────────────────────────────────────────────────────
HAS_IMAGE=$(printf '%s\n' "$UPDATED" | jq 'if .image or .dockerFile or .dockerComposeFile then true else false end')
if [[ "$HAS_IMAGE" == "false" ]]; then
  info "No image specified — adding default base image..."
  UPDATED=$(printf '%s\n' "$UPDATED" | jq -c '.image = "mcr.microsoft.com/devcontainers/base:ubuntu"')
  success "Added image: mcr.microsoft.com/devcontainers/base:ubuntu"
else
  info "Image already specified, skipping."
fi

# ── Ensure remoteUser is set correctly ────────────────────────────────────────
CURRENT_USER=$(printf '%s\n' "$UPDATED" | jq -r '.remoteUser // empty')
if [[ "$CURRENT_USER" != "$CONTAINER_USER" ]]; then
  info "Setting remoteUser to '${CONTAINER_USER}'..."
  UPDATED=$(printf '%s\n' "$UPDATED" | jq -c --arg u "$CONTAINER_USER" '.remoteUser = $u')
  success "remoteUser set to '${CONTAINER_USER}'"
else
  info "remoteUser already set to '${CONTAINER_USER}', skipping."
fi

# ── Ensure ~/forge directory mount ────────────────────────────────────────────
if [[ ! -d "$FORGE_HOME" ]]; then
  warn "${FORGE_HOME} not found — creating empty directory."
  mkdir -p "$FORGE_HOME"
fi

MOUNT_STR="source=${FORGE_HOME},target=${FORGE_TARGET},type=bind,consistency=cached"

HAS_MOUNT=$(printf '%s\n' "$UPDATED" | jq --arg m "$MOUNT_STR" \
  'if .mounts then (.mounts | map(select(. == $m)) | length > 0) else false end')

if [[ "$HAS_MOUNT" == "true" ]]; then
  info "~/forge mount already correct, skipping."
else
  info "Updating mount for ~/forge..."
  UPDATED=$(printf '%s\n' "$UPDATED" | jq -c \
    --arg target "$FORGE_TARGET" \
    --arg src "$FORGE_HOME" '
    .mounts = (
      [.mounts[]? | select(type == "string" and (contains($target) | not))]
      + ["source=\($src),target=\($target),type=bind,consistency=cached"]
    )')
  success "Mounted ${FORGE_HOME} -> ${FORGE_TARGET}"
fi

# ── Inject postCreateCommand to install ForgeCode CLI ─────────────────────────
info "Configuring ForgeCode install command..."
INSTALL_CMD='curl -fsSL https://forgecode.dev/cli | sh'

# Check if postCreateCommand already contains forge install
HAS_FORGE_INSTALL=$(printf '%s\n' "$UPDATED" | jq -r '.postCreateCommand // ""' | grep -c 'forgecode.dev/cli' || true)

if [[ "$HAS_FORGE_INSTALL" -eq 0 ]]; then
  HAS_POST_CMD=$(printf '%s\n' "$UPDATED" | jq 'if .postCreateCommand then true else false end')
  if [[ "$HAS_POST_CMD" == "true" ]]; then
    info "Appending ForgeCode install to existing postCreateCommand..."
    UPDATED=$(printf '%s\n' "$UPDATED" | jq -c --arg cmd "$INSTALL_CMD" \
      '.postCreateCommand = (.postCreateCommand + " && " + $cmd)')
  else
    info "Adding ForgeCode install as postCreateCommand..."
    UPDATED=$(printf '%s\n' "$UPDATED" | jq -c --arg cmd "$INSTALL_CMD" \
      '.postCreateCommand = $cmd')
  fi
  success "ForgeCode install configured in postCreateCommand."
else
  info "ForgeCode install already in postCreateCommand, skipping."
fi

# ── Write back only if changed ────────────────────────────────────────────────
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

# ── Ensure devcontainer CLI is available ──────────────────────────────────────
if ! command -v devcontainer &>/dev/null; then
  die "devcontainer CLI not found. Install it with: npm install -g @devcontainers/cli"
fi

# ── Stop any existing container for this workspace so mounts are re-applied ───
EXISTING=$(docker ps -q --filter "label=devcontainer.local_folder=$(pwd)" 2>/dev/null || true)
if [[ -n "$EXISTING" ]]; then
  if [[ "$CHANGED" == "true" ]]; then
    info "Stopping existing container so new config takes effect..."
    docker stop "$EXISTING" &>/dev/null
    docker rm "$EXISTING" &>/dev/null || true
  fi
fi

# ── Rebuild image if config changed ──────────────────────────────────────────
if [[ "$CHANGED" == "true" ]]; then
  info "Changes detected — rebuilding container (this may take a moment)..."
  devcontainer build --workspace-folder . || die "Build failed."
  success "Container rebuilt."
else
  info "No config changes — starting container as-is..."
fi

# ── Bring container up ───────────────────────────────────────────────────────
info "Bringing container up..."
UP_OUTPUT=$(devcontainer up --workspace-folder . 2>&1) || die "Failed to start container:\n${UP_OUTPUT}"

CONTAINER_ID=$(echo "$UP_OUTPUT" | grep -o '"containerId":"[^"]*"' | tail -1 | cut -d'"' -f4)

if [[ -z "$CONTAINER_ID" ]]; then
  warn "Could not detect container ID — will skip auto-stop on exit."
else
  success "Container running: ${CONTAINER_ID:0:12}"
fi

# ── Configure git identity inside the container ──────────────────────────────
if [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]]; then
  info "Setting git identity inside container..."
  devcontainer exec --workspace-folder . git config --global user.name "$GIT_NAME"
  devcontainer exec --workspace-folder . git config --global user.email "$GIT_EMAIL"
  success "Git identity set: $GIT_NAME <$GIT_EMAIL>"
fi

# ── Run forge inside the container ────────────────────────────────────────────
info "Launching forge inside the container..."
print ""
devcontainer exec --workspace-folder . forge || true

# ── Stop container when forge exits ───────────────────────────────────────────
if [[ -n "$CONTAINER_ID" ]]; then
  info "forge exited — stopping container ${CONTAINER_ID:0:12}..."
  docker stop "$CONTAINER_ID" &>/dev/null && success "Container stopped." || warn "Could not stop container — may already be stopped."
else
  warn "forge exited — stop the container manually with: docker ps"
fi
