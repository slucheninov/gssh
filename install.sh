#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${GSSH_HOME:-${HOME}/.gssh}"
GITHUB_RAW="https://raw.githubusercontent.com/slucheninov/gssh/master"

# --- Detect local repo or remote install ---
REPO_DIR=""
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_PATH" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
  if [[ -f "$SCRIPT_DIR/gssh.zsh" && -f "$SCRIPT_DIR/_gssh" ]]; then
    REPO_DIR="$SCRIPT_DIR"
  fi
fi

# --- Download helper (curl → wget fallback) ---
_download() {
  local url="$1" dest="$2"
  if command -v curl &>/dev/null; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget &>/dev/null; then
    wget -qO "$dest" "$url"
  else
    echo "Error: curl or wget is required" >&2
    exit 1
  fi
}

# --- Get file: copy local or download ---
_get_file() {
  local name="$1" dest="$2"
  if [[ -n "$REPO_DIR" ]]; then
    cp "$REPO_DIR/$name" "$dest"
  else
    _download "$GITHUB_RAW/$name" "$dest"
  fi
}

# --- Header ---
if [[ -f "$INSTALL_DIR/gssh.zsh" ]]; then
  echo "gssh updater"
  echo "============"
else
  echo "gssh installer"
  echo "=============="
fi
echo ""
if [[ -n "$REPO_DIR" ]]; then
  echo "Source: local ($REPO_DIR)"
else
  echo "Source: github (slucheninov/gssh)"
fi
echo "Install directory: $INSTALL_DIR"
echo ""

mkdir -p "$INSTALL_DIR"

# --- Install / update core files ---
for f in gssh.zsh _gssh; do
  tmpfile="$(mktemp)"
  if ! _get_file "$f" "$tmpfile"; then
    echo "Error: failed to get $f" >&2
    rm -f "$tmpfile"
    exit 1
  fi

  if [[ -f "$INSTALL_DIR/$f" ]]; then
    if ! diff -q "$tmpfile" "$INSTALL_DIR/$f" &>/dev/null; then
      mv "$tmpfile" "$INSTALL_DIR/$f"
      echo "Updated: $f"
    else
      rm -f "$tmpfile"
      echo "Up to date: $f"
    fi
  else
    mv "$tmpfile" "$INSTALL_DIR/$f"
    echo "Installed: $f"
  fi
done

# --- .env ---
if [[ -f "$INSTALL_DIR/.env" ]]; then
  echo "Existing .env found, keeping it."
else
  tmpfile="$(mktemp)"
  if _get_file ".env.example" "$tmpfile" 2>/dev/null; then
    mv "$tmpfile" "$INSTALL_DIR/.env"
    echo "Created .env from template (edit with your settings)"
  else
    rm -f "$tmpfile"
  fi
fi

# --- .zshrc snippet ---
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
