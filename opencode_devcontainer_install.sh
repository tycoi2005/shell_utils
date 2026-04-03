#!/usr/bin/env bash
set -euo pipefail

# Install script: generates opencode-devcontainer and places it in ~/.bin

INSTALL_DIR="$HOME/.bin"
CONFIG_DIR="$HOME/.bin/opencode_devcontainer_config"
TARGET="$INSTALL_DIR/opencode-devcontainer"
GIT_NAME="tycoi2005"
GIT_EMAIL="tycoi2005@opencode"
NAME_PROVIDED=false
EMAIL_PROVIDED=false

for arg in "$@"; do
  case "$arg" in
    --git-name=*)
      GIT_NAME="${arg#--git-name=}"
      NAME_PROVIDED=true
      ;;
    --git-email=*)
      GIT_EMAIL="${arg#--git-email=}"
      EMAIL_PROVIDED=true
      ;;
  esac
done

if [[ "$NAME_PROVIDED" == "false" ]]; then
  read -r -p "Enter default git user name [${GIT_NAME}]: " INPUT_NAME
  if [[ -n "$INPUT_NAME" ]]; then
    GIT_NAME="$INPUT_NAME"
  fi
fi

if [[ "$EMAIL_PROVIDED" == "false" ]]; then
  read -r -p "Enter default git user email [${GIT_EMAIL}]: " INPUT_EMAIL
  if [[ -n "$INPUT_EMAIL" ]]; then
    GIT_EMAIL="$INPUT_EMAIL"
  fi
fi

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"

# Generate opencode config
cat > "$CONFIG_DIR/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": "allow",
  "plugin": [
    "@nguquen/opencode-anthropic-auth@0.0.14"
  ]
}
EOF

cat > "$CONFIG_DIR/Dockerfile" <<'DOCKEREOF'
FROM node:22
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ripgrep jq fd-find bat less procps ca-certificates curl dnsutils iputils-ping tree unzip zip nano \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g opencode-ai
WORKDIR /workspace
DOCKEREOF

cat > "$TARGET" <<'INNEREOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/opencode_devcontainer_config"

TARGET_DIR=""
AUTO_INIT=true
DEVCONTAINER_IMAGE="node:22"
DEVCONTAINER_NAME="opencode-safe"
GIT_NAME="__GIT_NAME__"
GIT_EMAIL="__GIT_EMAIL__"
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
  cp "$CONFIG_DIR/Dockerfile" "$DEVCONTAINER_DIR/Dockerfile"
  cat > "$DEVCONTAINER_FILE" <<JSONEOF
{
  "name": "$DEVCONTAINER_NAME",
  "build": {
    "dockerfile": "Dockerfile"
  },
  "workspaceFolder": "/workspaces/\${localWorkspaceFolderBasename}",
  "postCreateCommand": "npm install -g opencode-ai",
  "remoteEnv": {
    "ANTHROPIC_API_KEY": "\${localEnv:ANTHROPIC_API_KEY}",
    "ANTHROPIC_AUTH_TOKEN": "\${localEnv:ANTHROPIC_AUTH_TOKEN}",
    "OPENAI_API_KEY": "\${localEnv:OPENAI_API_KEY}"
  },
  "mounts": [
    "source=\${localEnv:HOME}/.config/opencode/config.json,target=/root/.config/opencode/config.json,type=bind,consistency=cached",
    "source=\${localEnv:HOME}/.local/share/opencode/auth.json,target=/root/.local/share/opencode/auth.json,type=bind,consistency=cached",
    "source=\${localEnv:HOME}/.local/share/opencode-devcontainer,target=/root/.local/share/opencode,type=bind,consistency=cached",
    "source=\${localEnv:HOME}/.local/state/opencode-devcontainer,target=/root/.local/state/opencode,type=bind,consistency=cached"
  ]
}
JSONEOF
  printf 'Created %s\n' "$DEVCONTAINER_FILE"
fi

HOST_AUTH_FILE="$HOME/.local/share/opencode/auth.json"
HOST_RUNTIME_CONFIG_FILE="$HOME/.config/opencode/config.json"
OPENCODE_CONFIG="$CONFIG_DIR/opencode.json"

DATA_DIR="$HOME/.local/share/opencode-devcontainer"
STATE_DIR="$HOME/.local/state/opencode-devcontainer"
mkdir -p "$DATA_DIR"
mkdir -p "$STATE_DIR"

CONTAINER_ID=""

cleanup() {
  echo "Stopping devcontainer..."
  if [[ -n "$CONTAINER_ID" ]]; then
    docker stop "$CONTAINER_ID" 2>/dev/null || true
    docker rm -f "$CONTAINER_ID" 2>/dev/null || true
  fi
  devcontainer down --workspace-folder "$TARGET_DIR" 2>/dev/null || true
}

CONTAINER_ID=$(devcontainer up --workspace-folder "$TARGET_DIR" --remove-existing-container 2>/dev/null | grep -o '"containerId":"[^"]*"' | head -1 | cut -d'"' -f4 || true)

devcontainer exec --workspace-folder "$TARGET_DIR" sh -lc 'mkdir -p /root && cat > /root/.gitconfig' <<GITEOF
[user]
    name = $GIT_NAME
    email = $GIT_EMAIL
GITEOF

if [[ -f "$HOST_AUTH_FILE" ]]; then
  devcontainer exec --workspace-folder "$TARGET_DIR" sh -lc 'mkdir -p /root/.local/share/opencode && cat > /root/.local/share/opencode/auth.json' < "$HOST_AUTH_FILE"
fi

if [[ -f "$HOST_RUNTIME_CONFIG_FILE" ]]; then
  devcontainer exec --workspace-folder "$TARGET_DIR" sh -lc 'mkdir -p /root/.config/opencode && cat > /root/.config/opencode/config.json' < "$HOST_RUNTIME_CONFIG_FILE"
fi

if [[ -f "$OPENCODE_CONFIG" ]]; then
  devcontainer exec --workspace-folder "$TARGET_DIR" sh -lc 'mkdir -p /root/.config/opencode && cp /root/.config/opencode/opencode.json /root/.config/opencode/opencode.json.bak 2>/dev/null; cat > /root/.config/opencode/opencode.json' < "$OPENCODE_CONFIG"
fi

devcontainer exec --workspace-folder "$TARGET_DIR" sh -lc '
if ! opencode --version >/dev/null 2>&1; then
  npm install -g --force opencode-ai
fi
'

trap cleanup EXIT

if [[ ${#PASS_ARGS[@]} -gt 0 ]]; then
  devcontainer exec --workspace-folder "$TARGET_DIR" sh -lc 'exec opencode "$@"' _ "${PASS_ARGS[@]}"
else
  devcontainer exec --workspace-folder "$TARGET_DIR" sh -lc 'exec opencode'
fi
INNEREOF

chmod +x "$TARGET"

python3 - "$TARGET" "$GIT_NAME" "$GIT_EMAIL" <<'PYEOF'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
git_name = sys.argv[2]
git_email = sys.argv[3]
content = path.read_text()
content = content.replace("__GIT_NAME__", git_name)
content = content.replace("__GIT_EMAIL__", git_email)
path.write_text(content)
PYEOF

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
echo "Default git identity: $GIT_NAME <$GIT_EMAIL>"
