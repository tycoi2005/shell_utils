#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.bin"
TARGET="$INSTALL_DIR/check-docker-project"

mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/check_docker_project.sh" "$TARGET"
chmod +x "$TARGET"

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
echo "Run: check-docker-project"
