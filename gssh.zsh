#!/usr/bin/env zsh
# gssh - GCP IAP SSH helper with fzf support
# https://github.com/USER/gssh

# --- Configuration defaults (override in .zshrc or .env) ---
: ${GSSH_ZONES:="us-central1-a us-central1-b us-central1-c"}
: ${GSSH_PROJECTS:=""}
: ${GSSH_CACHE_FILE:="${HOME}/.cache/gssh/vms"}
: ${GSSH_CACHE_TTL:=86400}
: ${GSSH_EXCLUDE_PREFIXES:=""}

# --- Cache ---
function _gssh_refresh_cache() {
  local now=$(date +%s)
  local cache_time=0
  local -a projects=(${(s: :)GSSH_PROJECTS})

  if [[ -f "$GSSH_CACHE_FILE" ]]; then
    cache_time=$(stat -f %m "$GSSH_CACHE_FILE" 2>/dev/null \
              || stat -c %Y "$GSSH_CACHE_FILE" 2>/dev/null)
  fi

  if (( now - cache_time > GSSH_CACHE_TTL )) || [[ ! -f "$GSSH_CACHE_FILE" ]]; then
    mkdir -p "$(dirname "$GSSH_CACHE_FILE")"
    echo "gssh: refreshing VM cache..." >&2
    local tmpfile="$(mktemp)"
    if (( ${#projects} > 0 )); then
      for p in "${projects[@]}"; do
        gcloud compute instances list --project="$p" --format='value(name)' 2>/dev/null >> "$tmpfile"
      done
    else
      gcloud compute instances list --format='value(name)' 2>/dev/null > "$tmpfile"
    fi

    # Filter out excluded prefixes
    local -a excludes=(${(s: :)GSSH_EXCLUDE_PREFIXES})
    if (( ${#excludes} > 0 )); then
      local pattern="^($(IFS='|'; echo "${excludes[*]}"))"
      grep -Ev "$pattern" "$tmpfile" > "$GSSH_CACHE_FILE"
    else
      mv "$tmpfile" "$GSSH_CACHE_FILE"
      return
    fi
    rm -f "$tmpfile"
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
    echo "  gssh --list,    -l   List cached VM names"
    echo "  gssh --refresh, -r   Force-refresh the VM name cache"
    echo "  gssh --help,    -h   Show this help"
    echo ""
    echo "Extra SSH args can be passed after --:"
    echo "  gssh <vm-name> [project] [zone] -- -L 3306:localhost:3306"
    echo ""
    echo "Environment variables:"
    echo "  GSSH_PROJECTS    Space-separated list of GCP project IDs"
    echo "  GSSH_ZONES       Space-separated list of GCP zones (default: us-central1-{a,b,c})"
    echo "  GSSH_CACHE_FILE       Path to VM name cache (default: ~/.cache/gssh/vms)"
    echo "  GSSH_CACHE_TTL        Cache lifetime in seconds (default: 86400)"
    echo "  GSSH_EXCLUDE_PREFIXES Space-separated prefixes to exclude (e.g. gke-)"
    return 0
  fi

  if [[ "$1" == "--list" || "$1" == "-l" ]]; then
    _gssh_refresh_cache
    cat "$GSSH_CACHE_FILE"
    return 0
  fi

  if [[ "$1" == "--refresh" || "$1" == "-r" ]]; then
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
  local project="" zone=""
  local -a extra_args=()
  shift

  # Parse: [project] [zone] [-- extra-ssh-args...]
  while (( $# > 0 )); do
    if [[ "$1" == "--" ]]; then
      shift
      extra_args=("$@")
      break
    elif [[ -z "$project" ]]; then
      project="$1"
    elif [[ -z "$zone" ]]; then
      zone="$1"
    fi
    shift
  done

  local -a projects=(${(s: :)GSSH_PROJECTS})
  local -a zones=(${(s: :)GSSH_ZONES})

  if [[ -z "$project" ]]; then
    if (( ${#projects} == 0 )); then
      project=$(gcloud config get-value project 2>/dev/null)
      if [[ -z "$project" ]]; then
        echo "gssh: GSSH_PROJECTS is not set and no default gcloud project found." >&2
        echo "       Define GSSH_PROJECTS in .zshrc or .env, or run: gcloud config set project <id>" >&2
        return 1
      fi
      echo "gssh: using default gcloud project: $project" >&2
    elif (( ${#projects} == 1 )); then
      project="${projects[1]}"
    else
      project=$(_gssh_select "Select project:" "${projects[@]}")
    fi
  fi
  [[ -z "$project" ]] && return 1

  if [[ -z "$zone" ]]; then
    zone=$(_gssh_select "Select zone:" "${zones[@]}")
  fi
  [[ -z "$zone" ]] && return 1

  echo "gssh: connecting to $vm | project: $project | zone: $zone"
  if (( ${#extra_args} > 0 )); then
    gcloud compute ssh "$vm" --tunnel-through-iap --project="$project" --zone="$zone" -- "${extra_args[@]}"
  else
    gcloud compute ssh "$vm" --tunnel-through-iap --project="$project" --zone="$zone"
  fi
}
