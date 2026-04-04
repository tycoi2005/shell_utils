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

AUTH_TARGET="~/.local/share/opencode/auth.json"
MODEL_TARGET="~/.local/state/opencode/model.json"
CONFIG_TARGET="~/.config/opencode/config.json"

DEVCONTAINER_DIR=".devcontainer"
DEVCONTAINER_FILE="${DEVCONTAINER_DIR}/devcontainer.json"

GIT_NAME="tycoi2005"
GIT_EMAIL="tycoi2005@opencode"

for arg in "$@"; do
  case "$arg" in
    --git-name=*) GIT_NAME="${arg#--git-name=}" ;;
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

# ── 1. Create .devcontainer/devcontainer.json if missing ──────────────────────
if [[ ! -f "$DEVCONTAINER_FILE" ]]; then
  info "No devcontainer.json found — creating one."
  mkdir -p "$DEVCONTAINER_DIR"
  cat > "$DEVCONTAINER_FILE" <<'EOF'
{
  "name": "Dev Container",
  "features": {},
  "mounts": []
}
EOF
  success "Created ${DEVCONTAINER_FILE}"
fi

# ── 2. Read current file ───────────────────────────────────────────────────────
ORIGINAL=$(cat "$DEVCONTAINER_FILE")
UPDATED="$ORIGINAL"

# ── 3. Add opencode feature if missing ────────────────────────────────────────
HAS_FEATURE=$(echo "$UPDATED" | jq --arg f "$OPENCODE_FEATURE" \
  'if .features | has($f) then true else false end')

if [[ "$HAS_FEATURE" == "false" ]]; then
  info "Adding opencode feature..."
  UPDATED=$(echo "$UPDATED" | jq --arg f "$OPENCODE_FEATURE" \
    '.features[$f] = {}')
  success "Added feature: ${OPENCODE_FEATURE}"
else
  info "opencode feature already present, skipping."
fi

# ── 4. Mount helper ───────────────────────────────────────────────────────────
add_mount() {
  local src="$1" target="$2" label="$3"

  if [[ ! -f "$src" ]]; then
    warn "${label} not found at ${src} — skipping mount."
    return
  fi

  local mount_str="source=${src},target=${target},type=bind,consistency=cached"

  # Check if this target is already mounted
  local already
  already=$(echo "$UPDATED" | jq --arg t "$target" \
    'if .mounts then (.mounts | map(select(type == "string" and contains($t))) | length > 0) else false end')

  if [[ "$already" == "false" ]]; then
    info "Adding mount for ${label}..."
    UPDATED=$(echo "$UPDATED" | jq --arg m "$mount_str" \
      '.mounts = (if .mounts then .mounts else [] end) + [$m]')
    success "Mounted ${src} → ${target}"
  else
    info "${label} mount already present, skipping."
  fi
}

# ── 5. Add mounts ─────────────────────────────────────────────────────────────
add_mount "$AUTH_SRC"   "$AUTH_TARGET"    "auth.json"
add_mount "$MODEL_SRC"  "$MODEL_TARGET"   "model.json"
add_mount "$CONFIG_SRC" "$CONFIG_TARGET"  "opencode.json"

# ── 6. Write back only if changed ─────────────────────────────────────────────
if [[ "$UPDATED" == "$ORIGINAL" ]]; then
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

 
# ── 8. Rebuild if changed, then bring container up ────────────────────────────
if [[ "$CHANGED" == "true" ]]; then
  info "Changes detected — rebuilding container (this may take a moment)..."
  devcontainer build --workspace-folder . || error "Build failed."
  success "Container rebuilt."
else
  info "No config changes — starting container as-is..."
fi
 
info "Bringing container up..."
UP_OUTPUT=$(devcontainer up --workspace-folder . 2>&1) || error "Failed to start container:\n${UP_OUTPUT}"
 
# devcontainer up prints a JSON line at the end containing the containerId
CONTAINER_ID=$(echo "$UP_OUTPUT" | grep -o '"containerId":"[^"]*"' | tail -1 | cut -d'"' -f4)
 
if [[ -z "$CONTAINER_ID" ]]; then
  warn "Could not detect container ID — will skip auto-stop on exit."
else
  success "Container running: ${CONTAINER_ID:0:12}"
fi
 
# ── 9. Configure git identity inside the container ────────────────────────────
if [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]]; then
  info "Setting git identity inside container..."
  devcontainer exec --workspace-folder . git config --global user.name "$GIT_NAME"
  devcontainer exec --workspace-folder . git config --global user.email "$GIT_EMAIL"
  success "Git identity set: $GIT_NAME <$GIT_EMAIL>"
fi

# ── 10. Run opencode inside the container ──────────────────────────────────────
info "Launching opencode inside the container..."
print ""
devcontainer exec --workspace-folder . opencode || true
 
# ── 10. Stop container when opencode exits ────────────────────────────────────
if [[ -n "$CONTAINER_ID" ]]; then
  info "opencode exited — stopping container ${CONTAINER_ID:0:12}..."
  docker stop "$CONTAINER_ID" &>/dev/null && success "Container stopped." || warn "Could not stop container — may already be stopped."
else
  warn "opencode exited — stop the container manually with: docker ps"
fi