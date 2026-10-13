#!/usr/bin/env bats

load test_helper/setup

@test "completion shows a refresh hint when no VM matches" {
  run zsh -c '
    source "$GSSH_ROOT/gssh.zsh"
    _arguments() { state=vms; }
    _describe() { return 1; }
    _message() { [[ "$1" == -r ]] || return 1; shift; print -r -- "$@"; }
    words=(gssh coredns); CURRENT=2
    fpath=("$GSSH_ROOT" $fpath)
    autoload -Uz _gssh
    _gssh
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"No matching VMs in cache; run gssh --refresh"* ]]
}

@test "completion distinguishes a fetch failure from no matches" {
  export GSSH_MOCK_FAIL_LIST=1
  run zsh -c '
    source "$GSSH_ROOT/gssh.zsh"
    _arguments() { state=vms; }
    _message() { [[ "$1" == -r ]] || return 1; shift; print -r -- "$@"; }
    words=(gssh coredns); CURRENT=2
    fpath=("$GSSH_ROOT" $fpath)
    autoload -Uz _gssh
    _gssh
  '
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unable to refresh VM cache"* ]]
}
