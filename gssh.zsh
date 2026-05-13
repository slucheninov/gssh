#!/usr/bin/env zsh
# gssh - GCP IAP SSH helper with fzf support
# https://github.com/USER/gssh

GSSH_VERSION="1.1.7"

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
    local base name safe_account
    if [[ "$GSSH_CACHE_FILE" == */* ]]; then
      base="${GSSH_CACHE_FILE%/*}"
      name="${GSSH_CACHE_FILE##*/}"
    else
      base="."
      name="$GSSH_CACHE_FILE"
    fi
    safe_account="${account//[^A-Za-z0-9_-]/_}"
    echo "${base}/${safe_account}_${name}"
  else
    echo "$GSSH_CACHE_FILE"
  fi
}

function _gssh_cache_mtime() {
  local cache_file="$1"
  stat -f %m "$cache_file" 2>/dev/null \
    || stat -c %Y "$cache_file" 2>/dev/null
}

function _gssh_cache_is_legacy() {
  local cache_file="$1"
  local line

  [[ ! -s "$cache_file" ]] && return 1
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" != *$'\t'* ]]
    return
  done < "$cache_file"
  return 1
}

function _gssh_cache_needs_refresh() {
  local cache_file="$1"
  local force="${2:-false}"
  local now cache_time

  [[ "$force" == true ]] && return 0
  [[ ! -f "$cache_file" ]] && return 0
  _gssh_cache_is_legacy "$cache_file" && return 0

  now=$(date +%s)
  cache_time=$(_gssh_cache_mtime "$cache_file")
  [[ -z "$cache_time" ]] && return 0

  (( now - cache_time > GSSH_CACHE_TTL ))
}

function _gssh_is_excluded() {
  local name="$1"
  local prefix
  local -a excludes=(${(s: :)GSSH_EXCLUDE_PREFIXES})

  for prefix in "${excludes[@]}"; do
    [[ -z "$prefix" ]] && continue
    if [[ "${name[1,${#prefix}]}" == "$prefix" ]]; then
      return 0
    fi
  done
  return 1
}

function _gssh_append_cache_rows() {
  local tmpfile="$1"
  local project="$2"
  local output="$3"
  local line name zone
  local tab=$'\t'
  local -a cols

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    cols=(${=line})
    name="${cols[1]:-}"
    zone="${cols[2]:-}"
    [[ -z "$name" ]] && continue
    _gssh_is_excluded "$name" && continue
    print -r -- "${name}${tab}${project}${tab}${zone}" >> "$tmpfile"
  done <<< "$output"
}

function _gssh_fetch_project_instances() {
  local account="$1"
  local project="$2"
  local tmpfile="$3"
  local output _stderr_file
  local -a account_flag=()
  local -a project_flag=()

  [[ -n "$account" ]] && account_flag=(--account="$account")
  [[ -n "$project" ]] && project_flag=(--project="$project")

  _stderr_file="$(mktemp)"
  if ! output=$(gcloud compute instances list "${account_flag[@]}" "${project_flag[@]}" --format='value(name,zone.basename())' 2>"$_stderr_file"); then
    if [[ -n "$project" ]]; then
      echo "gssh: failed to list VMs for project $project" >&2
    else
      echo "gssh: failed to list VMs" >&2
    fi
    [[ -s "$_stderr_file" ]] && cat "$_stderr_file" >&2
    rm -f "$_stderr_file"
    return 1
  fi

  rm -f "$_stderr_file"
  _gssh_append_cache_rows "$tmpfile" "$project" "$output"
}

function _gssh_spinner() {
  local pid="$1"
  local msg="${2:-loading...}"
  local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=1

  if [[ ! -w /dev/tty ]]; then
    echo "  $msg" >&2
    return 0
  fi

  while kill -0 "$pid" 2>/dev/null; do
    printf '\r\033[K  %s %s' "${frames[i]}" "$msg" >/dev/tty
    i=$(( i % ${#frames} + 1 ))
    sleep 0.1
  done
  printf '\r\033[K' >/dev/tty
}

function _gssh_refresh_cache() {
  setopt local_options no_monitor
  local account="$1"
  local force="${2:-false}"
  local silent_errors="${3:-false}"
  local cache_file=$(_gssh_cache_file "$account")
  local -a projects=(${(s: :)GSSH_PROJECTS})
  local tmpfile errfile

  if ! _gssh_cache_needs_refresh "$cache_file" "$force"; then
    return 0
  fi

  mkdir -p "$(dirname "$cache_file")"
  tmpfile="$(mktemp)"
  errfile="$(mktemp)"

  (
    local p _default_project _any_success=false
    if (( ${#projects} > 0 )); then
      for p in "${projects[@]}"; do
        _gssh_fetch_project_instances "$account" "$p" "$tmpfile" && _any_success=true
      done
    else
      _default_project=$(gcloud config get-value project 2>/dev/null)
      [[ "$_default_project" == "(unset)" ]] && _default_project=""
      _gssh_fetch_project_instances "$account" "$_default_project" "$tmpfile" && _any_success=true
    fi
    [[ "$_any_success" == true ]] && exit 0
    exit 1
  ) 2>"$errfile" &
  local bg_pid=$!

  local _spinner_msg="gssh: refreshing VM cache..."
  [[ -n "$account" ]] && _spinner_msg="gssh: refreshing cache for $account..."
  _gssh_spinner "$bg_pid" "$_spinner_msg"

  wait "$bg_pid"
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    if [[ "$silent_errors" != true ]]; then
      [[ -s "$errfile" ]] && cat "$errfile" >&2
    fi
    rm -f "$tmpfile" "$errfile"
    return 1
  fi

  rm -f "$errfile"
  mv "$tmpfile" "$cache_file"
}

function _gssh_cached_vms() {
  local account="$1"
  local -a _all_accounts=(${(s: :)GSSH_ACCOUNTS})
  local name project zone cache_file
  local -A seen=()

  if [[ -z "$account" ]] && (( ${#_all_accounts} > 1 )); then
    local _acct
    for _acct in "${_all_accounts[@]}"; do
      _gssh_refresh_cache "$_acct" false true
      cache_file=$(_gssh_cache_file "$_acct")
      [[ ! -f "$cache_file" ]] && continue
      while IFS=$'\t' read -r name project zone; do
        [[ -z "$name" || -n "${seen[$name]}" ]] && continue
        seen[$name]=1
        print -r -- "$name"
      done < "$cache_file"
    done
  else
    cache_file=$(_gssh_cache_file "$account")
    _gssh_refresh_cache "$account" || return 1
    while IFS=$'\t' read -r name project zone; do
      [[ -z "$name" || -n "${seen[$name]}" ]] && continue
      seen[$name]=1
      print -r -- "$name"
    done < "$cache_file"
  fi
}

function _gssh_cached_projects() {
  local account="$1"
  local vm="${2:-}"
  local -a _all_accounts=(${(s: :)GSSH_ACCOUNTS})
  local name project zone cache_file
  local -A seen=()

  if [[ -z "$account" ]] && (( ${#_all_accounts} > 1 )); then
    local _acct
    for _acct in "${_all_accounts[@]}"; do
      _gssh_refresh_cache "$_acct" false true
      cache_file=$(_gssh_cache_file "$_acct")
      [[ ! -f "$cache_file" ]] && continue
      while IFS=$'\t' read -r name project zone; do
        [[ -z "$project" ]] && continue
        [[ -n "$vm" && "$name" != "$vm" ]] && continue
        if [[ -z "${seen[$project]}" ]]; then
          seen[$project]=1
          print -r -- "$project"
        fi
      done < "$cache_file"
    done
  else
    cache_file=$(_gssh_cache_file "$account")
    _gssh_refresh_cache "$account" || return 1
    while IFS=$'\t' read -r name project zone; do
      [[ -z "$project" ]] && continue
      [[ -n "$vm" && "$name" != "$vm" ]] && continue
      if [[ -z "${seen[$project]}" ]]; then
        seen[$project]=1
        print -r -- "$project"
      fi
    done < "$cache_file"
  fi
}

function _gssh_cached_zones() {
  local account="$1"
  local vm="${2:-}"
  local project_filter="${3:-}"
  local -a _all_accounts=(${(s: :)GSSH_ACCOUNTS})
  local name project zone cache_file
  local -A seen=()

  if [[ -z "$account" ]] && (( ${#_all_accounts} > 1 )); then
    local _acct
    for _acct in "${_all_accounts[@]}"; do
      _gssh_refresh_cache "$_acct" false true
      cache_file=$(_gssh_cache_file "$_acct")
      [[ ! -f "$cache_file" ]] && continue
      while IFS=$'\t' read -r name project zone; do
        [[ -z "$zone" ]] && continue
        [[ -n "$vm" && "$name" != "$vm" ]] && continue
        [[ -n "$project_filter" && "$project" != "$project_filter" ]] && continue
        if [[ -z "${seen[$zone]}" ]]; then
          seen[$zone]=1
          print -r -- "$zone"
        fi
      done < "$cache_file"
    done
  else
    cache_file=$(_gssh_cache_file "$account")
    _gssh_refresh_cache "$account" || return 1
    while IFS=$'\t' read -r name project zone; do
      [[ -z "$zone" ]] && continue
      [[ -n "$vm" && "$name" != "$vm" ]] && continue
      [[ -n "$project_filter" && "$project" != "$project_filter" ]] && continue
      if [[ -z "${seen[$zone]}" ]]; then
        seen[$zone]=1
        print -r -- "$zone"
      fi
    done < "$cache_file"
  fi
}

function _gssh_find_vm_account() {
  local vm="$1"
  local -a _all_accounts=(${(s: :)GSSH_ACCOUNTS})
  local _acct cache_file name project zone
  local -A _found=()

  for _acct in "${_all_accounts[@]}"; do
    cache_file=$(_gssh_cache_file "$_acct")
    [[ ! -f "$cache_file" ]] && continue
    while IFS=$'\t' read -r name project zone; do
      if [[ "$name" == "$vm" && -z "${_found[$_acct]}" ]]; then
        _found[$_acct]=1
        print -r -- "$_acct"
        break
      fi
    done < "$cache_file"
  done
  (( ${#_found} > 0 ))
}

function _gssh_validate_accounts() {
  local -a check_accounts=("$@")
  (( ${#check_accounts} == 0 )) && return 0

  local -a authed_accounts
  authed_accounts=(${(f)"$(gcloud auth list --format='value(account)' 2>/dev/null)"})

  local acct
  local -a missing=()
  for acct in "${check_accounts[@]}"; do
    if (( ! ${authed_accounts[(Ie)$acct]} )); then
      missing+=("$acct")
    fi
  done

  if (( ${#missing} > 0 )); then
    echo "gssh: the following accounts are not authenticated:" >&2
    for acct in "${missing[@]}"; do
      echo "  - $acct" >&2
    done
    echo "" >&2
    echo "Run the following to authenticate:" >&2
    for acct in "${missing[@]}"; do
      echo "  gcloud auth login $acct" >&2
    done
    return 1
  fi
  return 0
}

function _gssh_get_vms() {
  local account="$1"
  _gssh_cached_vms "$account"
}

function _gssh_shell_join() {
  local -a quoted=("${(@q)@}")
  print -r -- "${(j: :)quoted}"
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
          if (( $# < 2 )) || [[ "$2" == -* ]]; then
            echo "gssh: --account requires an email" >&2
            return 1
          fi
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
    local tmpdir tmpfile f staged
    local -a upgrade_files=(gssh.zsh _gssh)
    local -a changed_files=()
    local -a staged_paths=()
    local -A staged_by_file=()

    tmpdir="$(mktemp -d)"
    if [[ -z "$tmpdir" || ! -d "$tmpdir" ]]; then
      echo "gssh: failed to create temporary upgrade directory" >&2
      return 1
    fi

    for f in "${upgrade_files[@]}"; do
      tmpfile="$tmpdir/$f"
      if command -v curl &>/dev/null; then
        curl -fsSL "$github_raw/$f" -o "$tmpfile" 2>/dev/null
      elif command -v wget &>/dev/null; then
        wget -qO "$tmpfile" "$github_raw/$f" 2>/dev/null
      else
        echo "gssh: curl or wget is required for upgrade" >&2
        rm -rf "$tmpdir"
        return 1
      fi

      if [[ ! -s "$tmpfile" ]]; then
        echo "gssh: failed to download $f" >&2
        rm -rf "$tmpdir"
        return 1
      fi
    done

    mkdir -p "$install_dir" || {
      echo "gssh: failed to create install directory: $install_dir" >&2
      rm -rf "$tmpdir"
      return 1
    }

    for f in "${upgrade_files[@]}"; do
      tmpfile="$tmpdir/$f"
      [[ -f "$install_dir/$f" ]] && diff -q "$tmpfile" "$install_dir/$f" &>/dev/null && continue

      staged="$install_dir/.$f.tmp.$$"
      if ! cp "$tmpfile" "$staged"; then
        echo "gssh: failed to stage $f for upgrade" >&2
        (( ${#staged_paths} > 0 )) && rm -f "${staged_paths[@]}"
        rm -rf "$tmpdir"
        return 1
      fi
      changed_files+=("$f")
      staged_paths+=("$staged")
      staged_by_file[$f]="$staged"
    done

    for f in "${changed_files[@]}"; do
      if ! mv "${staged_by_file[$f]}" "$install_dir/$f"; then
        echo "gssh: failed to install $f" >&2
        (( ${#staged_paths} > 0 )) && rm -f "${staged_paths[@]}"
        rm -rf "$tmpdir"
        return 1
      fi
    done

    for f in "${upgrade_files[@]}"; do
      if (( ${changed_files[(Ie)$f]} > 0 )); then
        echo "  $f: updated"
        updated=true
      else
        echo "  $f: up to date"
      fi
    done

    rm -rf "$tmpdir"

    local new_version
    new_version=$(grep -m1 '^GSSH_VERSION=' "$install_dir/gssh.zsh" 2>/dev/null | cut -d'"' -f2)

    if [[ "$updated" == true ]]; then
      echo "gssh: upgraded to ${new_version:-unknown}. Run 'exec zsh' to reload."
    else
      echo "gssh: already at the latest version (${new_version:-$GSSH_VERSION})."
    fi
    return 0
  fi

  # Resolve account: single account auto-selects; multi-account deferred to commands
  local -a accounts=(${(s: :)GSSH_ACCOUNTS})
  if [[ -z "$account" ]] && (( ${#accounts} == 1 )); then
    account="${accounts[1]}"
  fi

  # Validate that accounts are authenticated in gcloud
  if [[ -n "$account" ]]; then
    _gssh_validate_accounts "$account" || return 1
  elif (( ${#accounts} > 0 )); then
    _gssh_validate_accounts "${accounts[@]}" || return 1
  fi

  # --- list ---
  if [[ "$cmd" == "list" ]]; then
    _gssh_get_vms "$account"
    return 0
  fi

  # --- refresh ---
  if [[ "$cmd" == "refresh" ]]; then
    if [[ -z "$account" ]] && (( ${#accounts} > 1 )); then
      local _total=0 _acct _cf
      for _acct in "${accounts[@]}"; do
        _gssh_refresh_cache "$_acct" true true
        _cf=$(_gssh_cache_file "$_acct")
        [[ -f "$_cf" ]] && (( _total += $(wc -l < "$_cf" | tr -d ' ') ))
      done
      echo "gssh: cache refreshed ($_total VMs across ${#accounts} accounts)"
    else
      local cache_file=$(_gssh_cache_file "$account")
      _gssh_refresh_cache "$account" true || return 1
      echo "gssh: cache refreshed ($(wc -l < "$cache_file" | tr -d ' ') VMs)"
    fi
    return 0
  fi

  # --- ssh ---
  if (( ${#positional} == 0 )); then
    echo "Usage: gssh [--account <email>] <vm-name> [project] [zone]" >&2
    echo "       gssh --help for more info" >&2
    return 1
  fi

  # Resolve account for SSH when multiple accounts are configured
  if [[ -z "$account" ]] && (( ${#accounts} > 1 )); then
    local _acct
    for _acct in "${accounts[@]}"; do
      _gssh_refresh_cache "$_acct" false true
    done
    local -a _vm_accounts=(${(f)"$(_gssh_find_vm_account "${positional[1]}")"})
    if (( ${#_vm_accounts} == 1 )); then
      account="${_vm_accounts[1]}"
    elif (( ${#_vm_accounts} > 1 )); then
      account=$(_gssh_select "Select account for ${positional[1]}:" "${_vm_accounts[@]}")
      [[ -z "$account" ]] && return 1
    else
      account=$(_gssh_select "Select account:" "${accounts[@]}")
      [[ -z "$account" ]] && return 1
    fi
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
      local -a cached_projects=(${(f)"$(_gssh_cached_projects "$account" "$vm" 2>/dev/null)"})
      if (( ${#cached_projects} == 1 )); then
        project="${cached_projects[1]}"
      else
        project=$(_gssh_select "Select project:" "${projects[@]}")
      fi
    fi
  fi
  [[ -z "$project" ]] && return 1

  if [[ -z "$zone" ]]; then
    local -a cached_zones=(${(f)"$(_gssh_cached_zones "$account" "$vm" "$project" 2>/dev/null)"})
    if (( ${#cached_zones} == 1 )); then
      zone="${cached_zones[1]}"
    elif (( ${#zones} == 1 )); then
      zone="${zones[1]}"
    else
      zone=$(_gssh_select "Select zone:" "${zones[@]}")
    fi
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
    _gssh_shell_join "${ssh_cmd[@]}"
    return 0
  fi

  # --- copy ---
  if [[ "$cmd" == "copy" ]]; then
    local display_cmd="$(_gssh_shell_join "${ssh_cmd[@]}")"
    if command -v pbcopy &>/dev/null; then
      echo "$display_cmd" | pbcopy
    elif command -v xclip &>/dev/null; then
      echo "$display_cmd" | xclip -selection clipboard
    elif command -v xsel &>/dev/null; then
      echo "$display_cmd" | xsel --clipboard
    else
      echo "gssh: no clipboard utility found (pbcopy/xclip/xsel)" >&2
      echo "$display_cmd"
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
