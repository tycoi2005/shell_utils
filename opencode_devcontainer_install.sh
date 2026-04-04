#!/usr/bin/env bash
set -euo pipefail

# Install script: copies opencode-devcontainer to ~/.bin

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.bin"
TARGET="$INSTALL_DIR/opencode-devcontainer"

mkdir -p "$INSTALL_DIR"

cp "$SCRIPT_DIR/opencode_devcontainer.sh" "$TARGET"
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
