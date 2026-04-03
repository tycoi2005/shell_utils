#!/usr/bin/env bash
set -euo pipefail

# opencode_docker_install.sh — Install opencode-docker to ~/.bin/opencode/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.bin"
CONFIG_DIR="$HOME/.bin/opencode_docker_config"
BIN_DIR="$HOME/.bin"
GIT_NAME="tycoi2005"
GIT_EMAIL="tycoi2005@opencode"
NAME_PROVIDED=false
EMAIL_PROVIDED=false

for arg in "$@"; do
  case "$arg" in
    --name=*)
      GIT_NAME="${arg#--name=}"
      NAME_PROVIDED=true
      ;;
    --email=*)
      GIT_EMAIL="${arg#--email=}"
      EMAIL_PROVIDED=true
      ;;
  esac
done

if [[ "$NAME_PROVIDED" == "false" ]]; then
  read -r -p "Enter git user name [${GIT_NAME}]: " INPUT_NAME
  if [[ -n "${INPUT_NAME}" ]]; then
    GIT_NAME="$INPUT_NAME"
  fi
fi

if [[ "$EMAIL_PROVIDED" == "false" ]]; then
  read -r -p "Enter git user email [${GIT_EMAIL}]: " INPUT_EMAIL
  if [[ -n "${INPUT_EMAIL}" ]]; then
    GIT_EMAIL="$INPUT_EMAIL"
  fi
fi

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"

# Generate Dockerfile
cat > "$CONFIG_DIR/Dockerfile" <<'DOCKEREOF'
FROM node:22

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ripgrep jq fd-find bat less procps ca-certificates curl dnsutils iputils-ping tree unzip zip nano \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g opencode-ai opencode-vibeguard @nguquen/opencode-anthropic-auth@0.0.14

WORKDIR /workspace

ENTRYPOINT ["opencode"]
CMD []
DOCKEREOF

# Generate gitconfig
cat > "$CONFIG_DIR/.gitconfig" <<EOF
[user]
	name = ${GIT_NAME}
	email = ${GIT_EMAIL}
EOF

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

# Generate default config
cat > "$CONFIG_DIR/opencode_docker.json" <<EOF
{
  "image": "opencode-sandbox",
  "build": false,
  "data_dir": "~/.local/share/opencode-docker/",
  "state_dir": "~/.local/state/opencode-docker/",
  "shared_auth_file": "~/.local/share/opencode/auth.json",
  "shared_runtime_config_file": "~/.config/opencode/config.json",
  "tmp_exec": true,
  "git_name": "${GIT_NAME}",
  "git_email": "${GIT_EMAIL}"
}
EOF

# Generate the launcher script
cat > "$INSTALL_DIR/opencode-docker" <<'INNEREOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/opencode_docker_config"
CONFIG_FILE="$CONFIG_DIR/opencode_docker.json"
IMAGE_NAME="opencode-sandbox"
DATA_DIR="$HOME/.local/share/opencode-docker"
STATE_DIR="$HOME/.local/state/opencode-docker"
SHARED_AUTH_FILE="$HOME/.local/share/opencode/auth.json"
SHARED_RUNTIME_CONFIG_FILE="$HOME/.config/opencode/config.json"
DOCKERFILE="$CONFIG_DIR/Dockerfile"
BUILD_CONTEXT="$CONFIG_DIR"
OPENCODE_CONFIG="$CONFIG_DIR/opencode.json"
GITCONFIG="$CONFIG_DIR/.gitconfig"
BUILD=true
TMP_EXEC=true
CLI_DOCKERFILE_SET=false
REBUILD=false
GIT_NAME=""
GIT_EMAIL=""

# Parse config if it exists
if [[ -f "$CONFIG_FILE" ]]; then
  if command -v jq &> /dev/null; then
    if [[ "$(jq -r '.build // false' "$CONFIG_FILE")" == "true" ]]; then
      BUILD=true
    else
      BUILD=false
    fi
    if jq -r '.image' "$CONFIG_FILE" &> /dev/null; then
      IMAGE_NAME="$(jq -r '.image' "$CONFIG_FILE")"
    fi
    if jq -r '.data_dir' "$CONFIG_FILE" &> /dev/null; then
      DATA_DIR="$(jq -r '.data_dir' "$CONFIG_FILE")"
      DATA_DIR="${DATA_DIR/#\~/$HOME}"
    fi
    if jq -r '.state_dir' "$CONFIG_FILE" &> /dev/null; then
      STATE_DIR="$(jq -r '.state_dir' "$CONFIG_FILE")"
      STATE_DIR="${STATE_DIR/#\~/$HOME}"
    fi
    if jq -r '.shared_auth_file' "$CONFIG_FILE" &> /dev/null; then
      CONFIG_SHARED_AUTH_FILE="$(jq -r '.shared_auth_file // empty' "$CONFIG_FILE")"
      if [[ -n "$CONFIG_SHARED_AUTH_FILE" ]]; then
        SHARED_AUTH_FILE="${CONFIG_SHARED_AUTH_FILE/#\~/$HOME}"
      else
        SHARED_AUTH_FILE=""
      fi
    fi
    if jq -r '.shared_runtime_config_file' "$CONFIG_FILE" &> /dev/null; then
      CONFIG_RUNTIME_CONFIG_FILE="$(jq -r '.shared_runtime_config_file // empty' "$CONFIG_FILE")"
      if [[ -n "$CONFIG_RUNTIME_CONFIG_FILE" ]]; then
        SHARED_RUNTIME_CONFIG_FILE="${CONFIG_RUNTIME_CONFIG_FILE/#\~/$HOME}"
      else
        SHARED_RUNTIME_CONFIG_FILE=""
      fi
    fi
    if jq -r '.tmp_exec' "$CONFIG_FILE" &> /dev/null; then
      if [[ "$(jq -r '.tmp_exec // true' "$CONFIG_FILE")" == "true" ]]; then
        TMP_EXEC=true
      else
        TMP_EXEC=false
      fi
    fi
    if jq -r '.dockerfile' "$CONFIG_FILE" &> /dev/null; then
      CONFIG_DOCKERFILE="$(jq -r '.dockerfile // empty' "$CONFIG_FILE")"
      if [[ -n "$CONFIG_DOCKERFILE" ]]; then
        CONFIG_DOCKERFILE="${CONFIG_DOCKERFILE/#\~/$HOME}"
        if [[ "$CONFIG_DOCKERFILE" != /* ]]; then
          CONFIG_DOCKERFILE="$(pwd)/$CONFIG_DOCKERFILE"
        fi
        DOCKERFILE="$CONFIG_DOCKERFILE"
        BUILD_CONTEXT="$(dirname "$DOCKERFILE")"
      fi
    fi
    GIT_NAME="$(jq -r '.git_name // empty' "$CONFIG_FILE")"
    GIT_EMAIL="$(jq -r '.git_email // empty' "$CONFIG_FILE")"
  else
    BUILD=true
  fi
fi

# Parse CLI arguments for overrides
TARGET_DIR="$(pwd)"
TARGET_SET=false
PASS_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dockerfile=*) DOCKERFILE="${1#--dockerfile=}"; CLI_DOCKERFILE_SET=true ;;
    -f) shift; DOCKERFILE="$1"; CLI_DOCKERFILE_SET=true ;;
    --rebuild) REBUILD=true ;;
    *)
      if [[ "$TARGET_SET" == "false" && -d "$1" ]]; then
        TARGET_DIR="$1"
        TARGET_SET=true
      else
        PASS_ARGS+=("$1")
      fi
      ;;
  esac
  shift
done

# Resolve Dockerfile priority: CLI > current dir > config > config_dir default
if [[ "$CLI_DOCKERFILE_SET" == "false" ]]; then
  if [[ -f "$(pwd)/Dockerfile" ]]; then
    DOCKERFILE="$(pwd)/Dockerfile"
  fi
fi

# Resolve Dockerfile to absolute path
if [[ "$DOCKERFILE" != /* ]]; then
  DOCKERFILE="$(pwd)/$DOCKERFILE"
fi
BUILD_CONTEXT="$(dirname "$DOCKERFILE")"

# Ensure data dir exists
mkdir -p "$DATA_DIR"
mkdir -p "$STATE_DIR"

AUTH_MOUNT_ARGS=()
if [[ -n "$SHARED_AUTH_FILE" && -f "$SHARED_AUTH_FILE" ]]; then
  AUTH_MOUNT_ARGS=(-v "$SHARED_AUTH_FILE:/root/.local/share/opencode/auth.json")
fi

RUNTIME_CONFIG_MOUNT_ARGS=()
if [[ -n "$SHARED_RUNTIME_CONFIG_FILE" && -f "$SHARED_RUNTIME_CONFIG_FILE" ]]; then
  RUNTIME_CONFIG_MOUNT_ARGS=(-v "$SHARED_RUNTIME_CONFIG_FILE:/root/.config/opencode/config.json")
fi

# Ensure Dockerfile exists
if [[ ! -f "$DOCKERFILE" ]]; then
  echo "Error: Dockerfile not found at $DOCKERFILE"
  exit 1
fi

TMP_MOUNT_OPTS="rw,nosuid,size=512m"
if [[ "$TMP_EXEC" == "true" ]]; then
  TMP_MOUNT_OPTS="rw,exec,nosuid,size=512m"
fi

# Build image if needed, requested, or forced via --rebuild
if [[ "$REBUILD" == "true" ]]; then
  echo "Rebuilding Docker image $IMAGE_NAME..."
  docker build --no-cache -t "$IMAGE_NAME" -f "$DOCKERFILE" "$BUILD_CONTEXT"
elif [[ "$BUILD" == "true" ]] || ! docker image inspect "$IMAGE_NAME" &> /dev/null; then
  echo "Building Docker image $IMAGE_NAME..."
  docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" "$BUILD_CONTEXT"
fi

# Resolve the target directory
if [[ "$TARGET_DIR" != /* ]]; then
  TARGET_DIR="$(pwd)/$TARGET_DIR"
fi

# Resolve to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
  echo "Error: Directory '$TARGET_DIR' does not exist"
  exit 1
}

# Run opencode in container
DOCKER_TTY_FLAGS=""
if [[ -t 0 && -t 1 ]]; then
  DOCKER_TTY_FLAGS="-it"
fi

DOCKER_ENV_ARGS=()
if [[ -n "$GIT_NAME" ]]; then
  DOCKER_ENV_ARGS+=(-e GIT_AUTHOR_NAME="$GIT_NAME" -e GIT_COMMITTER_NAME="$GIT_NAME")
fi
if [[ -n "$GIT_EMAIL" ]]; then
  DOCKER_ENV_ARGS+=(-e GIT_AUTHOR_EMAIL="$GIT_EMAIL" -e GIT_COMMITTER_EMAIL="$GIT_EMAIL")
fi

DOCKER_BASE_ARGS=(
  --rm
  -e HOME=/root
  -v "$TARGET_DIR:/workspace"
  -v "$DATA_DIR:/root/.local/share/opencode"
  "${AUTH_MOUNT_ARGS[@]}"
  -v "$STATE_DIR:/root/.local/state/opencode"
  "${RUNTIME_CONFIG_MOUNT_ARGS[@]}"
  -v "$OPENCODE_CONFIG:/root/.config/opencode/opencode.json:ro"
  -v "$GITCONFIG:/root/.gitconfig:ro"
  "${DOCKER_ENV_ARGS[@]}"
  -w /workspace
  --tmpfs "/tmp:$TMP_MOUNT_OPTS"
  --security-opt no-new-privileges
  --cap-drop=ALL
)

echo "Starting opencode in $TARGET_DIR"

if [[ ${#PASS_ARGS[@]} -gt 0 ]]; then
  if [[ -n "$DOCKER_TTY_FLAGS" ]]; then
    exec docker run $DOCKER_TTY_FLAGS "${DOCKER_BASE_ARGS[@]}" "$IMAGE_NAME" "${PASS_ARGS[@]}"
  else
    exec docker run "${DOCKER_BASE_ARGS[@]}" "$IMAGE_NAME" "${PASS_ARGS[@]}"
  fi
else
  exec docker run -it "${DOCKER_BASE_ARGS[@]}" "$IMAGE_NAME"
fi
INNEREOF

chmod +x "$INSTALL_DIR/opencode-docker"

# Ensure ~/.bin is on PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qF "$BIN_DIR"; then
  if [[ -n "${BASH_VERSION:-}" ]]; then
    SHELL_RC="$HOME/.bash_profile"
    [[ ! -f "$SHELL_RC" ]] && SHELL_RC="$HOME/.bashrc"
    [[ ! -f "$SHELL_RC" ]] && SHELL_RC="$HOME/.profile"
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    SHELL_RC="$HOME/.zshrc"
  else
    SHELL_RC="$HOME/.profile"
  fi
  echo "export PATH=\"\$HOME/.bin:\$PATH\"" >> "$SHELL_RC"
  echo "Added ~/.bin to PATH in $SHELL_RC — restart your shell or run: source $SHELL_RC"
fi

echo "Installed opencode-docker to $INSTALL_DIR"
echo ""
echo "Usage:"
echo "  opencode-docker                          # Run in current directory"
echo "  opencode-docker /path/to/dir             # Run in specific directory"
echo "  opencode-docker --dockerfile=./Dockerfile # Use custom Dockerfile"
echo "  opencode-docker -f ./Dockerfile          # Shorthand for custom Dockerfile"
echo "  opencode-docker --rebuild                # Force rebuild of Docker image"
echo ""
echo "Config: $CONFIG_DIR/opencode_docker.json"
echo "  Set \"dockerfile\": \"./path/to/Dockerfile\" in config for per-project use"
echo "  Default \"data_dir\" is isolated to avoid SQLite corruption"
echo "  Default \"state_dir\" is isolated to avoid SQLite corruption"
echo "  Set \"shared_auth_file\" to share host auth.json (empty to disable)"
echo "  Set \"shared_runtime_config_file\" to share model/provider preferences"
echo "  Set \"tmp_exec\": false to mount /tmp with noexec"
echo ""
echo "Opencode config: $CONFIG_DIR/opencode.json"
