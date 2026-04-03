#!/usr/bin/env bash
set -euo pipefail

# Install script: generates opencode-devcontainer and places it in ~/.bin

INSTALL_DIR="$HOME/.bin"
TARGET="$INSTALL_DIR/opencode-devcontainer"

mkdir -p "$INSTALL_DIR"

cat > "$TARGET" <<'INNEREOF'
#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR=""
AUTO_INIT=true
DEVCONTAINER_IMAGE="node:22"
DEVCONTAINER_NAME="opencode-safe"
PASS_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-init)
      AUTO_INIT=false
      ;;
    --image=*)
      DEVCONTAINER_IMAGE="${1#--image=}"
      ;;
    --name=*)
      DEVCONTAINER_NAME="${1#--name=}"
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        PASS_ARGS+=("$1")
        shift
      done
      break
      ;;
    *)
      if [[ -z "$TARGET_DIR" && -d "$1" ]]; then
        TARGET_DIR="$1"
      else
        PASS_ARGS+=("$1")
      fi
      ;;
  esac
  shift
done

if ! command -v devcontainer >/dev/null 2>&1; then
  echo "Error: devcontainer CLI is not installed."
  echo "Install it with: npm install -g @devcontainers/cli"
  exit 1
fi

if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="$(pwd)"
fi

if [[ "$TARGET_DIR" != /* ]]; then
  TARGET_DIR="$(pwd)/$TARGET_DIR"
fi

TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
  echo "Error: Directory does not exist: $TARGET_DIR"
  exit 1
}

DEVCONTAINER_DIR="$TARGET_DIR/.devcontainer"
DEVCONTAINER_FILE="$DEVCONTAINER_DIR/devcontainer.json"

if [[ ! -f "$DEVCONTAINER_FILE" ]]; then
  if [[ "$AUTO_INIT" == "false" ]]; then
    echo "Error: Missing $DEVCONTAINER_FILE and --no-init was set."
    exit 1
  fi

  mkdir -p "$DEVCONTAINER_DIR"
  cat > "$DEVCONTAINER_FILE" <<JSONEOF
{
  "name": "$DEVCONTAINER_NAME",
  "image": "$DEVCONTAINER_IMAGE",
  "workspaceFolder": "/workspaces/\${localWorkspaceFolderBasename}",
  "postCreateCommand": "npm install -g opencode-ai",
  "remoteEnv": {
    "ANTHROPIC_API_KEY": "\${localEnv:ANTHROPIC_API_KEY}",
    "ANTHROPIC_AUTH_TOKEN": "\${localEnv:ANTHROPIC_AUTH_TOKEN}",
    "OPENAI_API_KEY": "\${localEnv:OPENAI_API_KEY}"
  }
}
JSONEOF
  printf 'Created %s\n' "$DEVCONTAINER_FILE"
fi

devcontainer up --workspace-folder "$TARGET_DIR" --remove-existing-container

HOST_AUTH_FILE="$HOME/.local/share/opencode/auth.json"
HOST_RUNTIME_CONFIG_FILE="$HOME/.config/opencode/config.json"

if [[ -f "$HOST_AUTH_FILE" ]]; then
  devcontainer exec --workspace-folder "$TARGET_DIR" sh -lc 'mkdir -p /root/.local/share/opencode && cat > /root/.local/share/opencode/auth.json' < "$HOST_AUTH_FILE"
fi

if [[ -f "$HOST_RUNTIME_CONFIG_FILE" ]]; then
  devcontainer exec --workspace-folder "$TARGET_DIR" sh -lc 'mkdir -p /root/.config/opencode && cat > /root/.config/opencode/config.json' < "$HOST_RUNTIME_CONFIG_FILE"
fi

devcontainer exec --workspace-folder "$TARGET_DIR" sh -lc '
if ! opencode --version >/dev/null 2>&1; then
  npm install -g --force opencode-ai
fi
'

if [[ ${#PASS_ARGS[@]} -gt 0 ]]; then
  exec devcontainer exec --workspace-folder "$TARGET_DIR" sh -lc 'exec opencode "$@"' _ "${PASS_ARGS[@]}"
else
  exec devcontainer exec --workspace-folder "$TARGET_DIR" sh -lc 'exec opencode'
fi
INNEREOF

chmod +x "$TARGET"

# Ensure ~/.bin is on PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qF "$INSTALL_DIR"; then
  if [[ -n "${BASH_VERSION:-}" ]]; then
    SHELL_RC="$HOME/.bash_profile"
    [[ ! -f "$SHELL_RC" ]] && SHELL_RC="$HOME/.bashrc"
    [[ ! -f "$SHELL_RC" ]] && SHELL_RC="$HOME/.profile"
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    SHELL_RC="$HOME/.zshrc"
  else
    SHELL_RC="$HOME/.profile"
  fi
  echo 'export PATH="$HOME/.bin:$PATH"' >> "$SHELL_RC"
  echo "Added ~/.bin to PATH in $SHELL_RC - restart your shell or run: source $SHELL_RC"
fi

echo "Installed $TARGET"
echo "Run: opencode-devcontainer"
