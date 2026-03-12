#!/usr/bin/env zsh
# gssh - GCP IAP SSH helper with fzf support
# https://github.com/USER/gssh

# --- Configuration defaults (override in .zshrc or .env) ---
: ${GSSH_ZONES:="us-central1-a us-central1-b us-central1-c"}
: ${GSSH_PROJECTS:=""}
: ${GSSH_CACHE_FILE:="${HOME}/.cache/gssh/vms"}
: ${GSSH_CACHE_TTL:=86400}

# Split string values into arrays if not already arrays
typeset -a _GSSH_ZONES _GSSH_PROJECTS
_GSSH_ZONES=(${(s: :)GSSH_ZONES})
_GSSH_PROJECTS=(${(s: :)GSSH_PROJECTS})

# --- Cache ---
function _gssh_refresh_cache() {
  local now=$(date +%s)
  local cache_time=0

  if [[ -f "$GSSH_CACHE_FILE" ]]; then
    cache_time=$(stat -f %m "$GSSH_CACHE_FILE" 2>/dev/null \
              || stat -c %Y "$GSSH_CACHE_FILE" 2>/dev/null)
  fi

  if (( now - cache_time > GSSH_CACHE_TTL )) || [[ ! -f "$GSSH_CACHE_FILE" ]]; then
    mkdir -p "$(dirname "$GSSH_CACHE_FILE")"
    echo "gssh: refreshing VM cache..." >&2
    gcloud compute instances list --format='value(name)' 2>/dev/null > "$GSSH_CACHE_FILE"
  fi
}

function _gssh_get_vms() {
  _gssh_refresh_cache
  cat "$GSSH_CACHE_FILE"
}

# --- Selector helpers ---
function _gssh_select() {
  local prompt="$1"
  shift
  local -a items=("$@")

  if command -v fzf &>/dev/null; then
    printf '%s\n' "${items[@]}" | fzf --prompt="$prompt " --height=~10
  else
    local choice
    PS3="$prompt "
    select choice in "${items[@]}"; do
      echo "$choice"
      break
    done
  fi
}

# --- Main function ---
function gssh() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: gssh <vm-name> [project] [zone]"
    echo ""
    echo "SSH into a GCP VM via IAP tunnel."
    echo "If project/zone are omitted, an interactive selector is shown."
    echo ""
    echo "Commands:"
    echo "  gssh --refresh   Force-refresh the VM name cache"
    echo "  gssh --help      Show this help"
    echo ""
    echo "Environment variables:"
    echo "  GSSH_PROJECTS    Space-separated list of GCP project IDs"
    echo "  GSSH_ZONES       Space-separated list of GCP zones (default: us-central1-{a,b,c})"
    echo "  GSSH_CACHE_FILE  Path to VM name cache (default: ~/.cache/gssh/vms)"
    echo "  GSSH_CACHE_TTL   Cache lifetime in seconds (default: 86400)"
    return 0
  fi

  if [[ "$1" == "--refresh" ]]; then
    rm -f "$GSSH_CACHE_FILE"
    _gssh_refresh_cache
    echo "gssh: cache refreshed ($(wc -l < "$GSSH_CACHE_FILE" | tr -d ' ') VMs)"
    return 0
  fi

  if [[ -z "$1" ]]; then
    echo "Usage: gssh <vm-name> [project] [zone]" >&2
    echo "       gssh --help for more info" >&2
    return 1
  fi

  local vm="$1"
  local project="${2:-}"
  local zone="${3:-}"

  if [[ -z "$project" ]]; then
    if (( ${#_GSSH_PROJECTS} == 0 )); then
      echo "gssh: GSSH_PROJECTS is not set. Define it in .zshrc or .env" >&2
      return 1
    fi
    project=$(_gssh_select "Select project:" "${_GSSH_PROJECTS[@]}")
  fi
  [[ -z "$project" ]] && return 1

  if [[ -z "$zone" ]]; then
    zone=$(_gssh_select "Select zone:" "${_GSSH_ZONES[@]}")
  fi
  [[ -z "$zone" ]] && return 1

  echo "gssh: connecting to $vm | project: $project | zone: $zone"
  gcloud compute ssh "$vm" --tunnel-through-iap --project="$project" --zone="$zone"
}
