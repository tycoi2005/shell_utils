#!/usr/bin/env zsh
# setup-opencode-devcontainer.sh
# Adds opencode to a devcontainer.json (creates one if missing),
# mounts auth.json / model.json / opencode.json, and rebuilds if anything changed.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
OPENCODE_FEATURE="ghcr.io/danzilberdan/devcontainers/opencode:0"
OPENCODE_SHARE="${HOME}/.local/share/opencode"
OPENCODE_CONFIG="${HOME}/.config/opencode"

AUTH_SRC="${OPENCODE_SHARE}/auth.json"
MODEL_SRC="${HOME}/.local/state/opencode/model.json"
CONFIG_SRC="${OPENCODE_CONFIG}/opencode.json"
RUNTIME_CONFIG_SRC="${OPENCODE_CONFIG}/config.json"

# Mount directly to their final destinations for two-way sync (OAuth persistence)
AUTH_TARGET="/root/.local/share/opencode/auth.json"
MODEL_TARGET="/root/.local/state/opencode/model.json"
CONFIG_TARGET="/root/.config/opencode/opencode.json"
RUNTIME_CONFIG_TARGET="/root/.config/opencode/config.json"

DEVCONTAINER_DIR=".devcontainer"
DEVCONTAINER_FILE="${DEVCONTAINER_DIR}/devcontainer.json"

GIT_NAME="tycoi2005"
GIT_EMAIL="tycoi2005@opencode"

for arg in "$@"; do
  case "$arg" in
    --git-name=*)  GIT_NAME="${arg#--git-name=}" ;;
    --git-email=*) GIT_EMAIL="${arg#--git-email=}" ;;
  esac
done

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

# ── 1. Create .devcontainer/devcontainer.json if missing ──────────────────────
if [[ ! -f "$DEVCONTAINER_FILE" ]]; then
  info "No devcontainer.json found — creating one."
  mkdir -p "$DEVCONTAINER_DIR"
  cat > "$DEVCONTAINER_FILE" <<'EOF'
{
  "name": "Dev Container",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {},
  "mounts": []
}
EOF
  success "Created ${DEVCONTAINER_FILE}"
fi

# ── 2. Read current file ───────────────────────────────────────────────────────
ORIGINAL=$(cat "$DEVCONTAINER_FILE")
UPDATED="$ORIGINAL"

# ── 3. Add image if missing ───────────────────────────────────────────────────
HAS_IMAGE=$(echo "$UPDATED" | jq 'if .image or .dockerFile or .dockerComposeFile then true else false end')
if [[ "$HAS_IMAGE" == "false" ]]; then
  info "No image specified — adding default base image..."
  UPDATED=$(echo "$UPDATED" | jq '.image = "mcr.microsoft.com/devcontainers/base:ubuntu"')
  success "Added image: mcr.microsoft.com/devcontainers/base:ubuntu"
else
  info "Image already specified, skipping."
fi

# ── 4. Add opencode feature if missing ────────────────────────────────────────
HAS_FEATURE=$(echo "$UPDATED" | jq --arg f "$OPENCODE_FEATURE" \
  'if .features | has($f) then true else false end')
if [[ "$HAS_FEATURE" == "false" ]]; then
  info "Adding opencode feature..."
  UPDATED=$(echo "$UPDATED" | jq --arg f "$OPENCODE_FEATURE" '.features[$f] = {}')
  success "Added feature: ${OPENCODE_FEATURE}"
else
  info "opencode feature already present, skipping."
fi

# ── 5. Ensure correct mounts (remove stale, add missing) ─────────────────────
# Remove any mount whose target doesn't match what we want
remove_wrong_mounts() {
  local correct_target="$1" label="$2"
  # Find any mount that references this label's known filenames but with wrong target
  UPDATED=$(echo "$UPDATED" | jq \
    --arg ct "$correct_target" \
    --arg auth "opencode-auth.json" \
    --arg model "opencode/model.json" \
    --arg cfg "opencode/config.json" \
    --arg cfg2 "opencode/opencode.json" '
    .mounts = [
      .mounts[]? |
      select(
        type == "string" and (
          (contains("opencode-auth") or contains("opencode/auth") or
           contains("opencode/model") or contains("opencode/config") or
           contains("opencode/opencode")) |
          not
        ) or contains($ct)
      )
    ]')
}

ensure_mount() {
  local src="$1" target="$2" label="$3"

  if [[ ! -f "$src" ]]; then
    warn "${label} not found at ${src} — skipping."
    return
  fi

  local mount_str="source=${src},target=${target},type=bind,consistency=cached"

  # Check if exact correct mount already exists
  local has_exact
  has_exact=$(echo "$UPDATED" | jq --arg m "$mount_str" \
    'if .mounts then (.mounts | map(select(. == $m)) | length > 0) else false end')

  if [[ "$has_exact" == "true" ]]; then
    info "${label} mount already correct, skipping."
    return
  fi

  # Remove any existing mount touching this target's path fragments, then add correct one
  info "Updating mount for ${label}..."
  UPDATED=$(echo "$UPDATED" | jq \
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
ensure_mount "$CONFIG_SRC"         "$CONFIG_TARGET"         "opencode.json"
ensure_mount "$RUNTIME_CONFIG_SRC" "$RUNTIME_CONFIG_TARGET" "config.json"

# ── 6. Write back only if changed ─────────────────────────────────────────────
# Normalize both for comparison (jq sorts keys consistently)
ORIGINAL_NORM=$(echo "$ORIGINAL" | jq -Sc .)
UPDATED_NORM=$(echo "$UPDATED" | jq -Sc .)

if [[ "$UPDATED_NORM" == "$ORIGINAL_NORM" ]]; then
  success "devcontainer.json already up-to-date — nothing to write."
  CHANGED=false
else
  echo "$UPDATED" | jq '.' > "$DEVCONTAINER_FILE"
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

# ── 12. Run opencode inside the container ─────────────────────────────────────
info "Launching opencode inside the container..."
print ""
devcontainer exec --workspace-folder . opencode || true

# ── 13. Stop container when opencode exits ────────────────────────────────────
if [[ -n "$CONTAINER_ID" ]]; then
  info "opencode exited — stopping container ${CONTAINER_ID:0:12}..."
  docker stop "$CONTAINER_ID" &>/dev/null && success "Container stopped." || warn "Could not stop container — may already be stopped."
else
  warn "opencode exited — stop the container manually with: docker ps"
fi
