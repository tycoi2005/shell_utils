#!/usr/bin/env bash
set -euo pipefail

# Install script: generates claude_openrouter.sh and places it in ~/.bin

# 1. Resolve token: prefer --token= argument, then fall back to .env
TOKEN=""
OPUS_MODEL="qwen/qwen3.6-plus:free"
SONNET_MODEL="qwen/qwen3.6-plus:free"
HAIKU_MODEL="qwen/qwen3.6-plus:free"

for arg in "$@"; do
  case "$arg" in
    --token=*)   TOKEN="${arg#--token=}" ;;
    --opus=*)    OPUS_MODEL="${arg#--opus=}" ;;
    --sonnet=*)  SONNET_MODEL="${arg#--sonnet=}" ;;
    --haiku=*)   HAIKU_MODEL="${arg#--haiku=}" ;;
  esac
done

if [[ -z "$TOKEN" && -f .env ]]; then
  TOKEN=$(grep -E '(^| )ANTHROPIC_AUTH_TOKEN=' .env | head -1 | sed 's/.*ANTHROPIC_AUTH_TOKEN=//' | tr -d '"' | tr -d "'")
fi

if [[ -z "$TOKEN" ]]; then
  echo "Usage: $0 --token=your_openrouter_token [--opus=model] [--sonnet=model] [--haiku=model]"
  echo "  Or set ANTHROPIC_AUTH_TOKEN in .env in this directory"
  exit 1
fi

# 2. Generate claude_openrouter.sh
INSTALL_DIR="$HOME/.bin"
mkdir -p "$INSTALL_DIR"
TARGET="$INSTALL_DIR/claude_openrouter.sh"

cat > "$TARGET" <<INNEREOF
#!/usr/bin/env bash
export ANTHROPIC_BASE_URL=https://openrouter.ai/api
export ANTHROPIC_AUTH_TOKEN=${TOKEN}
export ANTHROPIC_DEFAULT_OPUS_MODEL="${OPUS_MODEL}"
export ANTHROPIC_DEFAULT_SONNET_MODEL="${SONNET_MODEL}"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="${HAIKU_MODEL}"
export USER_TYPE=ant

claude
INNEREOF

chmod +x "$TARGET"

# 3. Ensure ~/.bin is on PATH
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
  echo "export PATH=\"\$HOME/.bin:\$PATH\"" >> "$SHELL_RC"
  echo "Added ~/.bin to PATH in $SHELL_RC — restart your shell or run: source $SHELL_RC"
fi

echo "Installed $TARGET"
echo "Run: claude_openrouter.sh"
