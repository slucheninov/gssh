#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${GSSH_HOME:-${HOME}/.gssh}"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "gssh installer"
echo "=============="
echo ""
echo "Install directory: $INSTALL_DIR"
echo ""

mkdir -p "$INSTALL_DIR"

cp "$REPO_DIR/gssh.zsh"  "$INSTALL_DIR/gssh.zsh"
cp "$REPO_DIR/_gssh"     "$INSTALL_DIR/_gssh"

if [[ -f "$INSTALL_DIR/.env" ]]; then
  echo "Existing .env found in $INSTALL_DIR, keeping it."
elif [[ -f "$REPO_DIR/.env" ]]; then
  cp "$REPO_DIR/.env" "$INSTALL_DIR/.env"
  echo "Copied .env to $INSTALL_DIR/.env"
elif [[ -f "$REPO_DIR/.env.example" ]]; then
  cp "$REPO_DIR/.env.example" "$INSTALL_DIR/.env"
  echo "Copied .env.example to $INSTALL_DIR/.env (edit with your settings)"
fi

SNIPPET='# gssh - GCP IAP SSH helper
[[ -f "${HOME}/.gssh/gssh.zsh" ]] && source "${HOME}/.gssh/gssh.zsh"
[[ -f "${HOME}/.gssh/.env" ]] && source "${HOME}/.gssh/.env"
fpath=("${HOME}/.gssh" $fpath)'

echo ""
echo "Files installed to $INSTALL_DIR"
echo ""

if grep -q "gssh.zsh" "${HOME}/.zshrc" 2>/dev/null; then
  echo "~/.zshrc already contains gssh config. Skipping."
else
  echo "Add the following to your ~/.zshrc (BEFORE compinit):"
  echo ""
  echo "$SNIPPET"
  echo ""
  read -rp "Add automatically? [y/N] " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    # Insert before compinit line if it exists, otherwise append
    if grep -n "^autoload.*compinit" "${HOME}/.zshrc" &>/dev/null; then
      LINE=$(grep -n "^autoload.*compinit" "${HOME}/.zshrc" | head -1 | cut -d: -f1)
      {
        head -n $((LINE - 1)) "${HOME}/.zshrc"
        echo ""
        echo "$SNIPPET"
        echo ""
        tail -n +"$LINE" "${HOME}/.zshrc"
      } > "${HOME}/.zshrc.tmp"
      mv "${HOME}/.zshrc.tmp" "${HOME}/.zshrc"
      echo "Inserted before compinit in ~/.zshrc"
    else
      echo "" >> "${HOME}/.zshrc"
      echo "$SNIPPET" >> "${HOME}/.zshrc"
      echo "Appended to ~/.zshrc"
    fi
  fi
fi

echo ""
echo "Done! Run 'exec zsh' to reload."
