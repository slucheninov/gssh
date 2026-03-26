#!/usr/bin/env zsh
# gssh - GCP IAP SSH helper with fzf support
# https://github.com/USER/gssh

GSSH_VERSION="1.0.0"

# --- Configuration defaults (override in .zshrc or .env) ---
: ${GSSH_ZONES:="us-central1-a us-central1-b us-central1-c"}
: ${GSSH_PROJECTS:=""}
: ${GSSH_CACHE_FILE:="${HOME}/.cache/gssh/vms"}
: ${GSSH_CACHE_TTL:=86400}
: ${GSSH_EXCLUDE_PREFIXES:=""}
: ${GSSH_ACCOUNTS:=""}

# --- Cache ---
function _gssh_cache_file() {
  local account="$1"
  if [[ -n "$account" ]]; then
    local base="${GSSH_CACHE_FILE%/*}"
    local name="${GSSH_CACHE_FILE##*/}"
    echo "${base}/${account//[@.]/_}_${name}"
  else
    echo "$GSSH_CACHE_FILE"
  fi
}

function _gssh_refresh_cache() {
  local account="$1"
  local cache_file=$(_gssh_cache_file "$account")
  local now=$(date +%s)
  local cache_time=0
  local -a projects=(${(s: :)GSSH_PROJECTS})
  local -a account_flag=()

  if [[ -n "$account" ]]; then
    account_flag=(--account="$account")
  fi

  if [[ -f "$cache_file" ]]; then
    cache_time=$(stat -f %m "$cache_file" 2>/dev/null \
              || stat -c %Y "$cache_file" 2>/dev/null)
  fi

  if (( now - cache_time > GSSH_CACHE_TTL )) || [[ ! -f "$cache_file" ]]; then
    mkdir -p "$(dirname "$cache_file")"
    echo "gssh: refreshing VM cache..." >&2
    local tmpfile="$(mktemp)"
    if (( ${#projects} > 0 )); then
      for p in "${projects[@]}"; do
        gcloud compute instances list "${account_flag[@]}" --project="$p" --format='value(name)' 2>/dev/null >> "$tmpfile"
      done
    else
      gcloud compute instances list "${account_flag[@]}" --format='value(name)' 2>/dev/null > "$tmpfile"
    fi

    # Filter out excluded prefixes
    local -a excludes=(${(s: :)GSSH_EXCLUDE_PREFIXES})
    if (( ${#excludes} > 0 )); then
      local pattern="^($(IFS='|'; echo "${excludes[*]}"))"
      grep -Ev "$pattern" "$tmpfile" > "$cache_file"
    else
      mv "$tmpfile" "$cache_file"
      return
    fi
    rm -f "$tmpfile"
  fi
}

function _gssh_get_vms() {
  local account="$1"
  _gssh_refresh_cache "$account"
  cat "$(_gssh_cache_file "$account")"
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
  # Parse all flags first
  local account=""
  local cmd=""
  local -a positional=()
  local -a extra_args=()
  local parsing_flags=true

  while (( $# > 0 )); do
    if [[ "$parsing_flags" == true ]]; then
      case "$1" in
        --help|-h)
          cmd="help"
          ;;
        --list|-l)
          cmd="list"
          ;;
        --refresh|-r)
          cmd="refresh"
          ;;
        --upgrade|-u)
          cmd="upgrade"
          ;;
        --version|-V)
          cmd="version"
          ;;
        --dry-run|-d)
          cmd="dry-run"
          ;;
        --copy|-c)
          cmd="copy"
          ;;
        --account|-a)
          shift
          account="$1"
          ;;
        --)
          shift
          extra_args=("$@")
          break
          ;;
        -*)
          echo "gssh: unknown option: $1" >&2
          echo "       gssh --help for more info" >&2
          return 1
          ;;
        *)
          positional+=("$1")
          parsing_flags=false
          ;;
      esac
    else
      if [[ "$1" == "--" ]]; then
        shift
        extra_args=("$@")
        break
      fi
      positional+=("$1")
    fi
    shift
  done

  # --- help ---
  if [[ "$cmd" == "help" ]]; then
    echo "Usage: gssh [--account <email>] <vm-name> [project] [zone]"
    echo ""
    echo "SSH into a GCP VM via IAP tunnel."
    echo "If project/zone are omitted, an interactive selector is shown."
    echo ""
    echo "Commands:"
    echo "  gssh --list,    -l   List cached VM names"
    echo "  gssh --refresh, -r   Force-refresh the VM name cache"
    echo "  gssh --upgrade, -u   Update gssh to the latest version"
    echo "  gssh --version, -V   Show version"
    echo "  gssh --dry-run, -d   Show gcloud command without executing"
    echo "  gssh --copy,    -c   Copy SSH command to clipboard"
    echo "  gssh --account, -a   Select GCP account (or set GSSH_ACCOUNTS)"
    echo "  gssh --help,    -h   Show this help"
    echo ""
    echo "Extra SSH args can be passed after --:"
    echo "  gssh <vm-name> [project] [zone] -- -L 3306:localhost:3306"
    echo ""
    echo "Environment variables:"
    echo "  GSSH_PROJECTS         Space-separated list of GCP project IDs"
    echo "  GSSH_ZONES            Space-separated list of GCP zones (default: us-central1-{a,b,c})"
    echo "  GSSH_ACCOUNTS         Space-separated list of GCP account emails"
    echo "  GSSH_CACHE_FILE       Path to VM name cache (default: ~/.cache/gssh/vms)"
    echo "  GSSH_CACHE_TTL        Cache lifetime in seconds (default: 86400)"
    echo "  GSSH_EXCLUDE_PREFIXES Space-separated prefixes to exclude (e.g. gke-)"
    return 0
  fi

  # --- version ---
  if [[ "$cmd" == "version" ]]; then
    echo "gssh $GSSH_VERSION"
    return 0
  fi

  # --- upgrade ---
  if [[ "$cmd" == "upgrade" ]]; then
    local install_dir="${GSSH_HOME:-${HOME}/.gssh}"
    local github_raw="https://raw.githubusercontent.com/slucheninov/gssh/master"
    local updated=false

    for f in gssh.zsh _gssh; do
      local tmpfile="$(mktemp)"
      if command -v curl &>/dev/null; then
        curl -fsSL "$github_raw/$f" -o "$tmpfile" 2>/dev/null
      elif command -v wget &>/dev/null; then
        wget -qO "$tmpfile" "$github_raw/$f" 2>/dev/null
      else
        echo "gssh: curl or wget is required for upgrade" >&2
        rm -f "$tmpfile"
        return 1
      fi

      if [[ ! -s "$tmpfile" ]]; then
        echo "gssh: failed to download $f" >&2
        rm -f "$tmpfile"
        return 1
      fi

      if [[ -f "$install_dir/$f" ]] && diff -q "$tmpfile" "$install_dir/$f" &>/dev/null; then
        rm -f "$tmpfile"
        echo "  $f: up to date"
      else
        mv "$tmpfile" "$install_dir/$f"
        echo "  $f: updated"
        updated=true
      fi
    done

    if [[ "$updated" == true ]]; then
      echo "gssh: upgraded. Run 'exec zsh' to reload."
    else
      echo "gssh: already at the latest version."
    fi
    return 0
  fi

  # Resolve account if not explicitly provided
  local -a accounts=(${(s: :)GSSH_ACCOUNTS})
  if [[ -z "$account" ]] && (( ${#accounts} > 1 )); then
    account=$(_gssh_select "Select account:" "${accounts[@]}")
    [[ -z "$account" ]] && return 1
  elif [[ -z "$account" ]] && (( ${#accounts} == 1 )); then
    account="${accounts[1]}"
  fi

  # --- list ---
  if [[ "$cmd" == "list" ]]; then
    _gssh_refresh_cache "$account"
    cat "$(_gssh_cache_file "$account")"
    return 0
  fi

  # --- refresh ---
  if [[ "$cmd" == "refresh" ]]; then
    local cache_file=$(_gssh_cache_file "$account")
    rm -f "$cache_file"
    _gssh_refresh_cache "$account"
    echo "gssh: cache refreshed ($(wc -l < "$cache_file" | tr -d ' ') VMs)"
    return 0
  fi

  # --- ssh ---
  if (( ${#positional} == 0 )); then
    echo "Usage: gssh [--account <email>] <vm-name> [project] [zone]" >&2
    echo "       gssh --help for more info" >&2
    return 1
  fi

  local vm="${positional[1]}"
  local project="${positional[2]:-}"
  local zone="${positional[3]:-}"

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

  local -a account_flag=()
  if [[ -n "$account" ]]; then
    account_flag=(--account="$account")
  fi

  local -a ssh_cmd=(gcloud compute ssh "$vm" "${account_flag[@]}" --tunnel-through-iap --project="$project" --zone="$zone")
  if (( ${#extra_args} > 0 )); then
    ssh_cmd+=(-- "${extra_args[@]}")
  fi

  # --- dry-run ---
  if [[ "$cmd" == "dry-run" ]]; then
    echo "${ssh_cmd[*]}"
    return 0
  fi

  # --- copy ---
  if [[ "$cmd" == "copy" ]]; then
    if command -v pbcopy &>/dev/null; then
      echo "${ssh_cmd[*]}" | pbcopy
    elif command -v xclip &>/dev/null; then
      echo "${ssh_cmd[*]}" | xclip -selection clipboard
    elif command -v xsel &>/dev/null; then
      echo "${ssh_cmd[*]}" | xsel --clipboard
    else
      echo "gssh: no clipboard utility found (pbcopy/xclip/xsel)" >&2
      echo "${ssh_cmd[*]}"
      return 1
    fi
    echo "gssh: command copied to clipboard"
    return 0
  fi

  # --- connect ---
  if [[ -n "$account" ]]; then
    echo "gssh: connecting to $vm | account: $account | project: $project | zone: $zone"
  else
    echo "gssh: connecting to $vm | project: $project | zone: $zone"
  fi
  "${ssh_cmd[@]}"
}
