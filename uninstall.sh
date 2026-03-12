#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${GSSH_HOME:-${HOME}/.gssh}"

echo "gssh uninstaller"
echo "================"
echo ""

if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR"
  echo "Removed $INSTALL_DIR"
else
  echo "$INSTALL_DIR not found, skipping."
fi

# Remove cache
rm -f "${HOME}/.cache/gssh/vms"
rmdir "${HOME}/.cache/gssh" 2>/dev/null || true
echo "Removed cache"

echo ""
echo "Don't forget to remove the gssh block from ~/.zshrc"
echo "Then run 'exec zsh' to reload."
