#!/usr/bin/env bash
# xo-afk-launch.sh - the single owner of away-mode ENTRY and EXIT: the
# read-back-and-confirm entry that writes the away-posture record through
# bin/xo-afk-contract.sh, and the away-mode daemon TERMINAL lifecycle where a
# daemon still runs: launch it in a NON-VISIBLE tracked terminal per backend,
# record its exact id, tear it down by that exact id, and reconcile a leaked one
# after a crash.
#
# ENTRY (the posture record). `/afk [words]` is two steps so the captain hears
# the mandate back before it binds: `propose` compiles the words and clauses
# into a proposal and prints the read-back (bin/xo-afk-contract.sh owns the
# clause fields, the never-set, the refusal wording, and the record schema); `confirm` promotes it
# into state/.afk-contract and prints the entry announcement (hold-for-return
# only: no phone channel exists). The record is the posture in every harness.
# On Pi and pi-signed the entry ENDS there: the away daemon is no longer launched
# on Pi, the ordinary supervision session keeps running in both postures, and
# `start` refuses on those harnesses. Every other harness still runs the daemon
# for now, so `start` and `start-native` require the confirmed record before they
# launch the daemon.
# `stop` (the return, driven by bin/xo-afk-return.sh) shuts the daemon down,
# clears state/.afk last, and archives the record under state/afk-contracts/.
#
# Why the terminal lifecycle exists (docs/herdr-backend.md "Away-mode daemon terminal launch"):
# bin/xo-afk-start.sh execs the supervise daemon in the FOREGROUND of whatever
# terminal it is already in. Harnesses with a native in-pane tracked-background
# tool (claude, grok) run it there directly and it is fine. A harness with NO
# native background mechanism (pi) has to manufacture a terminal, and doing that
# by SPLITTING the captain's active pane visibly shrinks it - the regression this
# script fixes. Instead this creates a non-visible tracked terminal (a herdr tab/
# workspace with --no-focus, or a detached tmux session) that never touches the
# captain's active tab, and NEVER uses shell `&` (which herdr/codex can reap).
#
# Correct supervisor targeting: the daemon finds the captain pane to inject into
# from its OWN inherited env (discover_supervisor_target). Running it in a
# separate terminal would make it discover its OWN pane, so this captures the
# captain pane FIRST (from the pane this script runs in) and passes it in as
# XO_SUPERVISOR_TARGET/XO_SUPERVISOR_BACKEND explicitly.
#
# Usage:
#   xo-afk-launch.sh propose [--words-file <path> | --words <text>]
#                            [--action <verb> --object <text> --when <text> [--stop <text>]]...
#                            [--expected-return <UTC ISO 8601>] [--spend <n>]
#                            [--grant <task-id>]...
#                              Record the captain's away words and mandate
#                              clause fields into a proposal and print the
#                              read-back. Exit 3 when a clause was refused (its
#                              missing part is named in the read-back); the
#                              proposal still records it as refused.
#                              Repeatable --grant records captain-named task
#                              ids that may merge-when-green while away.
#   xo-afk-launch.sh confirm   Promote the required proposal and print the entry
#                              announcement. On Pi this is the whole entry.
#   xo-afk-launch.sh start     Capture the captain pane, then (unless the daemon
#                              is already running) launch the daemon in a fresh
#                              non-visible terminal for the detected backend and
#                              record it. Idempotent: an already-running daemon
#                              just refreshes state/.afk; a recorded-but-dead
#                              terminal is reconciled (closed by id) first.
#   xo-afk-launch.sh start-native
#                              Prepare lifecycle state for a harness-native
#                              background job and record that no terminal exists.
#   xo-afk-launch.sh stop      Correct-ordered exit: SIGTERM the daemon so its
#                              cleanup flushes WHILE state/.afk is still present,
#                              wait for it, close the recorded terminal by exact
#                              id, clear state/.afk, then archive the record last.
#   xo-afk-launch.sh reconcile Close a recorded-but-dead daemon terminal by exact
#                              id and drop the record (recovery after a crash).
#
# Supported backends: herdr, tmux. Others (zellij, orca, cmux) have no verified
# non-visible-launch primitive here yet and refuse loudly.
#
# Test seam: XO_AFK_LAUNCH_ENTRY overrides the command run in the created
# terminal (default bin/xo-afk-start.sh), so a topology test can run a harmless
# placeholder instead of a real daemon. XO_SUPERVISOR_TARGET/XO_SUPERVISOR_BACKEND
# override the captured captain pane/backend (an isolated lab pane in tests).
set -u

XO_AFK_LAUNCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XO_ROOT="${XO_ROOT_OVERRIDE:-$(cd "$XO_AFK_LAUNCH_DIR/.." && pwd)}"
XO_HOME="${XO_HOME:-${XO_ROOT_OVERRIDE:-$XO_ROOT}}"
case "$XO_HOME" in
  /*) ;;
  *)
    XO_AFK_LAUNCH_HOME_INPUT=$XO_HOME
    XO_HOME=$(CDPATH='' cd -- "$XO_AFK_LAUNCH_HOME_INPUT" 2>/dev/null && pwd -P) || {
      echo "error: XO_HOME directory cannot be resolved: $XO_AFK_LAUNCH_HOME_INPUT" >&2
      exit 1
    }
    ;;
esac
if [ -n "${XO_STATE_OVERRIDE:-}" ]; then
  case "$XO_STATE_OVERRIDE" in
    /*) ;;
    *)
      XO_AFK_LAUNCH_STATE_INPUT=$XO_STATE_OVERRIDE
      XO_STATE_OVERRIDE=$(CDPATH='' cd -- "$XO_AFK_LAUNCH_STATE_INPUT" 2>/dev/null && pwd -P) || {
        echo "error: XO_STATE_OVERRIDE directory cannot be resolved: $XO_AFK_LAUNCH_STATE_INPUT" >&2
        exit 1
      }
      ;;
  esac
fi
XO_AFK_LAUNCH_STATE="${XO_STATE_OVERRIDE:-$XO_HOME/state}"
XO_AFK_LAUNCH_RECORD="$XO_AFK_LAUNCH_STATE/.afk-daemon-terminal"
XO_AFK_LAUNCH_LOCK="$XO_AFK_LAUNCH_STATE/.afk-launch.lock"
XO_AFK_LAUNCH_WS_LABEL="xo-afk-daemon"

# shellcheck source=bin/xo-backend.sh
. "$XO_AFK_LAUNCH_DIR/xo-backend.sh"
# shellcheck source=bin/xo-supervisor-target-lib.sh
. "$XO_AFK_LAUNCH_DIR/xo-supervisor-target-lib.sh"
# xo-afk-start.sh provides the daemon-lock liveness helpers and
# xo_afk_clear_stale_artifacts; it is sourceable (BASH_SOURCE guard) and its
# main does not run on source. It sets `set -eu`, so turn errexit back off for
# this script's best-effort flow immediately after.
# shellcheck source=bin/xo-afk-start.sh
. "$XO_AFK_LAUNCH_DIR/xo-afk-start.sh"
set +e
# The away-posture record owner; sourced for its path helpers, driven as a
# command for every record mutation so its output reaches the captain.
# shellcheck source=bin/xo-afk-contract.sh
. "$XO_AFK_LAUNCH_DIR/xo-afk-contract.sh"
XO_AFK_CONTRACT_CMD="$XO_AFK_LAUNCH_DIR/xo-afk-contract.sh"

xo_afk_launch_log() { printf 'xo-afk-launch: %s\n' "$*" >&2; }

xo_afk_launch_lock_owned() {
  local pid expected actual
  [ -d "$XO_AFK_LAUNCH_LOCK" ] || return 1
  pid=$(cat "$XO_AFK_LAUNCH_LOCK/pid" 2>/dev/null) || return 1
  expected=$(cat "$XO_AFK_LAUNCH_LOCK/pid-identity" 2>/dev/null) || return 1
  actual=$(xo_pid_identity "$pid" 2>/dev/null) || return 1
  [ -n "$expected" ] && [ "$actual" = "$expected" ]
}

xo_afk_launch_lock_acquire() {
  local attempt=0 incomplete=0 identity
  mkdir -p "$XO_AFK_LAUNCH_STATE" || return 1
  while [ "$attempt" -lt 200 ]; do
    attempt=$((attempt + 1))
    if mkdir "$XO_AFK_LAUNCH_LOCK" 2>/dev/null; then
      if ! printf '%s' "$$" > "$XO_AFK_LAUNCH_LOCK/pid"; then
        rm -rf "$XO_AFK_LAUNCH_LOCK"
        return 1
      fi
      identity=$(xo_pid_identity "$$" 2>/dev/null) || {
        rm -rf "$XO_AFK_LAUNCH_LOCK"
        return 1
      }
      if [ -z "$identity" ] || ! printf '%s' "$identity" > "$XO_AFK_LAUNCH_LOCK/pid-identity"; then
        rm -rf "$XO_AFK_LAUNCH_LOCK"
        return 1
      fi
      return 0
    fi
    if [ ! -s "$XO_AFK_LAUNCH_LOCK/pid" ] || [ ! -s "$XO_AFK_LAUNCH_LOCK/pid-identity" ]; then
      incomplete=$((incomplete + 1))
      if [ "$incomplete" -lt 20 ]; then
        sleep 0.05
        continue
      fi
    else
      incomplete=0
    fi
    if ! xo_afk_launch_lock_owned; then
      rm -rf "$XO_AFK_LAUNCH_LOCK" 2>/dev/null || return 1
      incomplete=0
      continue
    fi
    sleep 0.05
  done
  xo_afk_launch_log "timed out waiting for launcher lock"
  return 1
}

xo_afk_launch_lock_release() {
  local pid
  pid=$(cat "$XO_AFK_LAUNCH_LOCK/pid" 2>/dev/null || true)
  [ "$pid" = "$$" ] || return 0
  rm -rf "$XO_AFK_LAUNCH_LOCK"
}

xo_afk_launch_usage() {
  sed -n '/^# Usage:/,/^# Supported backends:/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

xo_afk_launch_primary_harness() {
  "$XO_AFK_LAUNCH_DIR/xo-harness.sh" 2>/dev/null || printf unknown
}

# The away daemon is no longer launched on Pi: the posture record is the whole
# entry there and the ordinary supervision session runs in both postures.
xo_afk_launch_daemon_allowed() {
  local harness
  harness=$(xo_afk_launch_primary_harness)
  case "$harness" in
    pi|pi-signed)
      xo_afk_launch_log "the away daemon is no longer launched on $harness; the away-posture record is the posture there (run bin/xo-afk-launch.sh confirm and stop)"
      return 1 ;;
  esac
  return 0
}

xo_afk_launch_catchup_pending() {
  if [ -e "$XO_AFK_LAUNCH_STATE/.afk-return-catchup" ]; then
    xo_afk_launch_log "return catch-up is still pending; run bin/xo-afk-return.sh check before re-entering away mode"
    return 0
  fi
  return 1
}

xo_afk_launch_record_require() {
  local record
  record=$(xo_afk_contract_path "$XO_AFK_LAUNCH_STATE")
  if ! xo_afk_contract_present "$XO_AFK_LAUNCH_STATE"; then
    xo_afk_launch_log "a confirmed away-posture record is required; run propose and confirm before starting the daemon"
    return 1
  fi
  xo_afk_contract_validate "$record" 1 || {
    xo_afk_launch_log "the away-posture record is not confirmed; run confirm before starting the daemon"
    return 1
  }
}

xo_afk_launch_propose() {
  xo_afk_launch_catchup_pending && return 1
  "$XO_AFK_CONTRACT_CMD" propose "$@"
}

xo_afk_launch_confirm() {
  xo_afk_launch_catchup_pending && return 1
  "$XO_AFK_CONTRACT_CMD" confirm
}

# The command run inside the created terminal. Real launch runs the shared
# daemon entry; a test overrides it with a harmless placeholder.
xo_afk_launch_entry_cmd() {
  printf '%s' "${XO_AFK_LAUNCH_ENTRY:-$XO_ROOT/bin/xo-afk-start.sh}"
}

xo_afk_launch_record_write() {  # <backend> <target> <extra>
  local pending
  mkdir -p "$XO_AFK_LAUNCH_STATE" || return 1
  pending=$(mktemp "$XO_AFK_LAUNCH_STATE/.afk-daemon-terminal.pending.XXXXXX") || return 1
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" > "$pending" || { rm -f "$pending"; return 1; }
  mv "$pending" "$XO_AFK_LAUNCH_RECORD" || { rm -f "$pending"; return 1; }
}

xo_afk_launch_flag_write() {
  xo_afk_flag_write "$XO_AFK_LAUNCH_STATE"
}

# Read the recorded terminal into XO_AFK_REC_BACKEND/XO_AFK_REC_TARGET. The third
# field (a herdr workspace id, kept for the record's own documentation) is not
# needed to close by id, so it is discarded. Returns 1 when no record exists.
xo_afk_launch_record_read() {
  local extra record
  XO_AFK_REC_BACKEND=""; XO_AFK_REC_TARGET=""; extra=""
  [ -f "$XO_AFK_LAUNCH_RECORD" ] || return 1
  record=$(cat "$XO_AFK_LAUNCH_RECORD" 2>/dev/null) || record=""
  IFS=$'\t' read -r XO_AFK_REC_BACKEND XO_AFK_REC_TARGET extra \
    < "$XO_AFK_LAUNCH_RECORD" || true
  if ! printf '%s\n' "$record" | awk -F '\t' 'NF != 3 { bad=1 } END { exit !(NR == 1 && !bad) }' \
    || [ -z "$XO_AFK_REC_BACKEND" ] || [ -z "$XO_AFK_REC_TARGET" ]; then
    xo_afk_launch_log "daemon terminal record is malformed; refusing to act on it"
    return 2
  fi
  case "$XO_AFK_REC_BACKEND" in
    herdr) [ -n "$extra" ] ;;
    tmux) : ;;
    none) [ "$XO_AFK_REC_TARGET" = - ] && [ "$extra" = native ] ;;
    *) return 2 ;;
  esac || { xo_afk_launch_log "daemon terminal record is malformed; refusing to act on it"; return 2; }
}

xo_afk_launch_record_validate_if_present() {
  local result
  xo_afk_launch_record_read
  result=$?
  [ "$result" -ne 2 ]
}

# Close a recorded terminal by EXACT id (never a broad sweep). The
# recorded workspace id (herdr) needs no separate close: closing the pane takes
# its single-tab dedicated workspace with it.
xo_afk_launch_close_terminal() {  # <backend> <target>
  local backend=$1 target=$2
  case "$backend" in
    herdr)
      xo_backend_source herdr || return 1
      local session=${target%%:*} pane=${target#*:}
      [ -n "$session" ] && [ -n "$pane" ] && [ "$pane" != "$target" ] || return 1
      xo_backend_herdr_cli "$session" pane close "$pane" >/dev/null 2>&1
      ;;
    tmux)
      # target is the dedicated daemon session name - kill exactly it.
      tmux kill-session -t "$target" 2>/dev/null
      ;;
    none)
      return 0
      ;;
    *)
      xo_afk_launch_log "cannot close unknown recorded backend '$backend'"
      return 1
      ;;
  esac
}

xo_afk_launch_terminal_absent() {  # <backend> <target>
  local backend=$1 target=$2 session pane out result code
  case "$backend" in
    herdr)
      session=${target%%:*}
      pane=${target#*:}
      [ -n "$session" ] && [ -n "$pane" ] && [ "$pane" != "$target" ] || return 1
      out=$(xo_backend_herdr_cli "$session" pane get "$pane" 2>&1)
      result=$?
      [ "$result" -ne 0 ] || return 1
      code=$(printf '%s' "$out" | jq -r '.error.code // empty' 2>/dev/null) || return 1
      [ "$code" = pane_not_found ]
      ;;
    tmux)
      out=$(tmux has-session -t "$target" 2>&1)
      result=$?
      [ "$result" -eq 1 ] || return 1
      printf '%s' "$out" | grep -Eq "can't find session"
      ;;
    none)
      return 0
      ;;
    *) return 1 ;;
  esac
}

xo_afk_launch_close_recorded() {
  local close_result=0
  xo_afk_launch_close_terminal "$XO_AFK_REC_BACKEND" "$XO_AFK_REC_TARGET" || close_result=$?
  if xo_afk_launch_terminal_absent "$XO_AFK_REC_BACKEND" "$XO_AFK_REC_TARGET"; then
    rm -f "$XO_AFK_LAUNCH_RECORD" || return 1
    [ "$close_result" -eq 0 ] || xo_afk_launch_log "terminal close command failed, but exact absence was confirmed"
    return 0
  fi
  xo_afk_launch_log "recorded terminal teardown is unconfirmed; preserving exact id"
  return 1
}

xo_afk_launch_terminal_alive() {  # <backend> <target>
  local backend=$1 target=$2 session pane
  case "$backend" in
    herdr)
      session=${target%%:*}
      pane=${target#*:}
      [ -n "$session" ] && [ -n "$pane" ] && [ "$pane" != "$target" ] || return 1
      xo_backend_herdr_cli "$session" pane get "$pane" >/dev/null 2>&1
      ;;
    tmux)
      tmux has-session -t "$target" 2>/dev/null
      ;;
    *) return 1 ;;
  esac
}

xo_afk_launch_wait_ready() {  # <backend> <target>
  local backend=$1 target=$2 attempt=0
  if [ -n "${XO_AFK_LAUNCH_ENTRY:-}" ]; then
    xo_afk_launch_terminal_alive "$backend" "$target"
    return
  fi
  while [ "$attempt" -lt 100 ]; do
    attempt=$((attempt + 1))
    daemon_lock_held_by_live_daemon && return 0
    xo_afk_launch_terminal_alive "$backend" "$target" || return 1
    sleep 0.05
  done
  return 1
}

xo_afk_launch_commit_terminal() {  # <backend> <target> <extra> [already-recorded]
  local backend=$1 target=$2 extra=$3 already_recorded=${4:-0}
  if [ "$already_recorded" -ne 1 ] && ! xo_afk_launch_record_write "$backend" "$target" "$extra"; then
    xo_afk_launch_log "failed to persist daemon terminal record; closing $backend:$target"
    xo_afk_launch_close_terminal "$backend" "$target"
    return 1
  fi
  if ! xo_afk_launch_wait_ready "$backend" "$target"; then
    xo_afk_launch_log "daemon did not become ready; closing $backend:$target"
    XO_AFK_REC_BACKEND=$backend
    XO_AFK_REC_TARGET=$target
    xo_afk_launch_close_recorded
    return 1
  fi
}

xo_afk_launch_herdr_recover_created() {  # <session> <label>
  local session=$1 label=$2 workspaces ws_count wsid panes pane_count pane attempt=0
  while [ "$attempt" -lt 20 ]; do
    attempt=$((attempt + 1))
    workspaces=$(xo_backend_herdr_cli "$session" workspace list 2>/dev/null) || { sleep 0.05; continue; }
    ws_count=$(printf '%s' "$workspaces" | jq --arg want "$label" \
      '[.result.workspaces[]? | select(.label == $want)] | length' 2>/dev/null) || { sleep 0.05; continue; }
    if [ "$ws_count" = 0 ]; then
      sleep 0.05
      continue
    fi
    [ "$ws_count" = 1 ] || return 1
    wsid=$(printf '%s' "$workspaces" | jq -r --arg want "$label" \
      '.result.workspaces[]? | select(.label == $want) | .workspace_id' 2>/dev/null) || return 1
    [ -n "$wsid" ] || return 1
    panes=$(xo_backend_herdr_cli "$session" pane list --workspace "$wsid" 2>/dev/null) || { sleep 0.05; continue; }
    pane_count=$(printf '%s' "$panes" | jq '[.result.panes[]?] | length' 2>/dev/null) || { sleep 0.05; continue; }
    if [ "$pane_count" = 0 ]; then
      sleep 0.05
      continue
    fi
    [ "$pane_count" = 1 ] || return 1
    pane=$(printf '%s' "$panes" | jq -r '.result.panes[0].pane_id // empty' 2>/dev/null) || return 1
    [ -n "$pane" ] || return 1
    printf '%s\t%s' "$wsid" "$pane"
    return 0
  done
  return 1
}

# Reconcile a recorded-but-dead terminal: if a record exists and no live daemon
# owns it, close the leaked terminal by exact id and drop the record.
xo_afk_launch_reconcile() {
  local read_result
  if daemon_lock_held_by_live_daemon; then
    return 0
  fi
  xo_afk_launch_record_read
  read_result=$?
  if [ "$read_result" -eq 0 ]; then
    xo_afk_launch_log "reconciling leaked daemon terminal ${XO_AFK_REC_BACKEND}:${XO_AFK_REC_TARGET}"
    xo_afk_launch_close_recorded
  elif [ "$read_result" -eq 2 ]; then
    return 1
  fi
}

xo_afk_launch_restore_backup() {  # <backup> <had-afk>
  local backup=$1 had_afk=$2 artifact result=0
  rm -f "$XO_AFK_LAUNCH_STATE/.afk" \
    "$XO_AFK_LAUNCH_STATE/.subsuper-escalations" \
    "$XO_AFK_LAUNCH_STATE/.subsuper-escalations.since" \
    "$XO_AFK_LAUNCH_STATE/.subsuper-inject-wedged" || result=1
  if [ "$had_afk" -eq 1 ]; then
    cp "$backup/.afk" "$XO_AFK_LAUNCH_STATE/.afk" || result=1
  fi
  for artifact in .subsuper-escalations .subsuper-escalations.since .subsuper-inject-wedged; do
    if [ -e "$backup/$artifact" ]; then
      cp -p "$backup/$artifact" "$XO_AFK_LAUNCH_STATE/$artifact" || result=1
    fi
  done
  if [ "$result" -eq 0 ]; then
    rm -rf "$backup" || return 1
  else
    xo_afk_launch_log "rollback restoration incomplete; backup retained at $backup"
  fi
  return "$result"
}

# Launch the daemon in a non-visible herdr terminal in the CAPTAIN's session
# (so the daemon can inject into the captain pane, which lives there). A
# dedicated background workspace (--no-focus) holds exactly one tab/pane; it
# never touches the captain's active tab. Prints the record line on success.
xo_afk_launch_create_herdr() {  # <captain-target> <captain-backend>
  local captain_target=$1 captain_backend=$2 session out wsid pane entry cmd label recovered create_result
  session=${captain_target%%:*}
  if [ -z "$session" ] || [ "$session" = "$captain_target" ]; then
    xo_afk_launch_log "cannot derive herdr session from captain target '$captain_target'"
    return 1
  fi
  xo_backend_source herdr || return 1
  xo_backend_herdr_server_ensure "$session" || { xo_afk_launch_log "herdr server not ready for session '$session'"; return 1; }
  label=${XO_AFK_LAUNCH_LABEL:-"$XO_AFK_LAUNCH_WS_LABEL-$$-${RANDOM:-0}-$(date '+%s')"}
  out=$(xo_backend_herdr_cli "$session" workspace create --cwd "$XO_HOME" --label "$label" --no-focus 2>/dev/null)
  create_result=$?
  wsid=$(printf '%s' "$out" | jq -r '.result.workspace.workspace_id // empty' 2>/dev/null)
  pane=$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id // empty' 2>/dev/null)
  if [ "$create_result" -ne 0 ] && [ -n "$wsid" ] && [ -n "$pane" ]; then
    xo_afk_launch_log "herdr create failed after returning exact ids; closing $session:$pane"
    if xo_afk_launch_record_write herdr "$session:$pane" "$wsid"; then
      XO_AFK_REC_BACKEND=herdr
      XO_AFK_REC_TARGET="$session:$pane"
      xo_afk_launch_close_recorded || true
    else
      xo_afk_launch_log "failed to persist exact id for failed herdr create"
    fi
    return 1
  fi
  if [ -z "$wsid" ] || [ -z "$pane" ]; then
    recovered=$(xo_afk_launch_herdr_recover_created "$session" "$label") || {
      xo_afk_launch_log "herdr create did not yield a recoverable exact workspace/pane id"
      return 1
    }
    IFS=$'\t' read -r wsid pane <<< "$recovered"
  fi
  entry=$(xo_afk_launch_entry_cmd)
  cmd=$(printf 'exec env XO_HOME=%q XO_SUPERVISOR_TARGET=%q XO_SUPERVISOR_BACKEND=%q %q' \
    "$XO_HOME" "$captain_target" "$captain_backend" "$entry")
  if ! xo_afk_launch_record_write herdr "$session:$pane" "$wsid"; then
    xo_afk_launch_log "failed to persist herdr daemon terminal record; closing $session:$pane"
    xo_afk_launch_close_terminal herdr "$session:$pane"
    return 1
  fi
  if ! xo_backend_herdr_cli "$session" pane run "$pane" "$cmd" >/dev/null 2>&1; then
    xo_afk_launch_log "failed to run daemon in herdr pane $session:$pane; closing it"
    XO_AFK_REC_BACKEND=herdr
    XO_AFK_REC_TARGET="$session:$pane"
    xo_afk_launch_close_recorded || true
    return 1
  fi
  xo_afk_launch_commit_terminal herdr "$session:$pane" "$wsid" 1 || return 1
  xo_afk_launch_log "daemon launched in non-visible herdr workspace $wsid (pane $session:$pane), supervising $captain_target"
}

# Launch the daemon in a detached tmux session (never a split-window in the
# captain's window). tmux pane ids are server-global, so the daemon reaches the
# captain pane by its %id from this separate session.
xo_afk_launch_create_tmux() {  # <captain-target> <captain-backend>
  local captain_target=$1 captain_backend=$2 session entry cmd hash nonce
  hash=$(printf '%s' "$XO_HOME" | cksum | cut -d' ' -f1)
  nonce="$$-${RANDOM:-0}-$(date '+%s')"
  session="xo-afk-daemon-$hash-$nonce"
  entry=$(xo_afk_launch_entry_cmd)
  cmd=$(printf 'exec env XO_HOME=%q XO_SUPERVISOR_TARGET=%q XO_SUPERVISOR_BACKEND=%q %q' \
    "$XO_HOME" "$captain_target" "$captain_backend" "$entry")
  if ! xo_afk_launch_record_write tmux "$session" ""; then
    xo_afk_launch_log "failed to persist planned tmux daemon session '$session'"
    return 1
  fi
  if ! tmux new-session -d -s "$session" "$cmd" 2>/dev/null; then
    xo_afk_launch_log "failed to create detached tmux daemon session '$session'"
    if ! rm -f "$XO_AFK_LAUNCH_RECORD"; then
      xo_afk_launch_log "failed to remove planned tmux daemon record after creation failure"
    fi
    return 1
  fi
  xo_afk_launch_commit_terminal tmux "$session" "" 1 || return 1
  xo_afk_launch_log "daemon launched in detached tmux session '$session', supervising $captain_target"
}

xo_afk_launch_start() {
  local captain_target captain_backend backup artifact had_afk=0 result
  xo_afk_launch_catchup_pending && return 1
  xo_afk_launch_daemon_allowed || return 1
  xo_afk_launch_record_require || return 1
  # Capture the captain pane FIRST, before creating anything.
  captain_target=$(discover_supervisor_target) || {
    xo_afk_launch_log "could not resolve the captain supervisor pane (set XO_SUPERVISOR_TARGET)"
    return 1; }
  captain_backend=$(discover_supervisor_backend) || {
    xo_afk_launch_log "could not resolve the captain supervisor backend (set XO_SUPERVISOR_BACKEND)"
    return 1; }

  mkdir -p "$XO_AFK_LAUNCH_STATE"

  if daemon_lock_held_by_live_daemon; then
    xo_afk_launch_record_validate_if_present || return 1
    if ! xo_afk_launch_flag_write; then
      xo_afk_launch_log "failed to refresh away-mode flag"
      return 1
    fi
    xo_afk_launch_log "daemon already running; refreshed away-mode flag (no new terminal)"
    return 0
  fi

  backup=$(mktemp -d "$XO_AFK_LAUNCH_STATE/.afk-launch-backup.XXXXXX") || return 1
  if [ -f "$XO_AFK_LAUNCH_STATE/.afk" ]; then
    had_afk=1
    cp "$XO_AFK_LAUNCH_STATE/.afk" "$backup/.afk" || { rm -rf "$backup"; return 1; }
  fi
  for artifact in .subsuper-escalations .subsuper-escalations.since .subsuper-inject-wedged; do
    if [ -e "$XO_AFK_LAUNCH_STATE/$artifact" ]; then
      cp -p "$XO_AFK_LAUNCH_STATE/$artifact" "$backup/$artifact" || { rm -rf "$backup"; return 1; }
    fi
  done
  if ! xo_afk_launch_reconcile; then
    result=1
  else
    if xo_afk_clear_stale_artifacts "$XO_AFK_LAUNCH_STATE"; then
      result=0
    else
      xo_afk_launch_log "failed to clear stale away-mode artifacts"
      result=1
    fi
  fi
  if [ "$result" -eq 0 ]; then
    if ! xo_afk_launch_flag_write; then
      xo_afk_launch_log "failed to write away-mode flag"
      result=1
    fi
  fi

  if [ "$result" -eq 0 ]; then
    case "$captain_backend" in
      herdr) xo_afk_launch_create_herdr "$captain_target" "$captain_backend"; result=$? ;;
      tmux)  xo_afk_launch_create_tmux "$captain_target" "$captain_backend"; result=$? ;;
      *)
        xo_afk_launch_log "no non-visible daemon-launch primitive for backend '$captain_backend' yet (supported: herdr, tmux)"
        result=1
        ;;
    esac
  fi
  if [ "$result" -ne 0 ]; then
    xo_afk_launch_restore_backup "$backup" "$had_afk" || result=1
  else
    rm -rf "$backup" || result=1
  fi
  return "$result"
}

xo_afk_launch_start_native() {
  local backup artifact had_afk=0 result=0
  mkdir -p "$XO_AFK_LAUNCH_STATE" || return 1
  xo_afk_launch_catchup_pending && return 1
  xo_afk_launch_daemon_allowed || return 1
  xo_afk_launch_record_require || return 1
  if daemon_lock_held_by_live_daemon; then
    xo_afk_launch_record_validate_if_present || return 1
    xo_afk_launch_flag_write || return 1
    xo_afk_launch_log "daemon already running; refreshed away-mode flag"
    return 0
  fi
  backup=$(mktemp -d "$XO_AFK_LAUNCH_STATE/.afk-launch-backup.XXXXXX") || return 1
  if [ -f "$XO_AFK_LAUNCH_STATE/.afk" ]; then
    had_afk=1
    cp "$XO_AFK_LAUNCH_STATE/.afk" "$backup/.afk" || { rm -rf "$backup"; return 1; }
  fi
  for artifact in .subsuper-escalations .subsuper-escalations.since .subsuper-inject-wedged; do
    if [ -e "$XO_AFK_LAUNCH_STATE/$artifact" ]; then
      cp -p "$XO_AFK_LAUNCH_STATE/$artifact" "$backup/$artifact" || { rm -rf "$backup"; return 1; }
    fi
  done
  xo_afk_launch_reconcile || result=1
  if [ "$result" -eq 0 ]; then
    if ! xo_afk_clear_stale_artifacts "$XO_AFK_LAUNCH_STATE"; then
      xo_afk_launch_log "failed to clear stale away-mode artifacts"
      result=1
    elif ! xo_afk_launch_flag_write; then
      result=1
    fi
  fi
  if [ "$result" -eq 0 ]; then
    xo_afk_launch_record_write none - native || result=1
  fi
  if [ "$result" -ne 0 ]; then
    xo_afk_launch_restore_backup "$backup" "$had_afk" || result=1
  else
    rm -rf "$backup" || result=1
  fi
  return "$result"
}

xo_afk_launch_stop() {
  local pid pid_identity current_identity result=0 read_result archived
  xo_afk_launch_record_read
  read_result=$?
  if [ "$read_result" -eq 2 ]; then
    xo_afk_launch_log "malformed daemon terminal record; refusing to stop away mode"
    return 1
  fi
  # (1) SIGTERM the daemon so its cleanup trap flushes buffered escalations
  # WHILE state/.afk is still present (the exit-ordering fix: clearing .afk
  # first would make that flush a no-op via inject_msg's presence gate).
  pid=""
  pid_identity=""
  if daemon_lock_held_by_live_daemon; then
    pid=$(daemon_lock_pid 2>/dev/null) || return 1
    pid_identity=$(xo_pid_identity "$pid" 2>/dev/null) || return 1
  fi
  if [ -n "$pid" ]; then
    if ! kill -TERM "$pid" 2>/dev/null; then
      xo_afk_launch_log "failed to signal away-mode daemon pid=$pid"
      result=1
    fi
    for _ in $(seq 1 40); do
      xo_pid_alive "$pid" || break
      sleep 0.25
    done
  fi
  if [ -n "$pid" ] && xo_pid_alive "$pid"; then
    current_identity=$(xo_pid_identity "$pid" 2>/dev/null) || {
      xo_afk_launch_log "could not confirm away-mode daemon exit; preserving lifecycle state"
      return 1
    }
    if [ "$current_identity" = "$pid_identity" ]; then
      xo_afk_launch_log "away-mode daemon did not exit after SIGTERM; preserving lifecycle state"
      return 1
    fi
  fi
  # (2) Close the daemon's own terminal by exact id.
  if [ "$read_result" -eq 0 ]; then
    xo_afk_launch_close_recorded || result=1
  fi
  # (3) Clear the away-mode flag, then (4) archive the posture record LAST so the
  # posture ends only once every daemon-side artifact is down.
  if ! rm -f "$XO_AFK_LAUNCH_STATE/.afk"; then
    xo_afk_launch_log "failed to clear away-mode flag"
    result=1
  fi
  if [ "$result" -eq 0 ] && xo_afk_contract_present "$XO_AFK_LAUNCH_STATE"; then
    if archived=$("$XO_AFK_CONTRACT_CMD" archive); then
      xo_afk_launch_log "away-posture record archived at $archived"
    else
      xo_afk_launch_log "failed to archive the away-posture record; it still stands"
      result=1
    fi
  fi
  if [ "$result" -eq 0 ]; then
    xo_afk_launch_log "away mode stopped; daemon terminal torn down, .afk cleared, and the posture record archived"
  else
    xo_afk_launch_log "away mode stopped; terminal teardown or the record archive remains recorded for retry"
  fi
  return "$result"
}

xo_afk_launch_main() {
  local result
  # Traps first, lock second. Acquiring before the handlers exist leaves a
  # window where a signal terminates this process by default action and leaks
  # the lock directory, which then blocks the next away-mode launch until the
  # stale-owner reclaim path clears it. xo_afk_launch_lock_release only removes
  # a lock this process owns, so arming it before acquisition is safe.
  trap xo_afk_launch_lock_release EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  xo_afk_launch_lock_acquire || return 1
  case "${1:-start}" in
    propose) shift; xo_afk_launch_propose "$@" ;;
    confirm) xo_afk_launch_confirm ;;
    start) xo_afk_launch_start ;;
    start-native) xo_afk_launch_start_native ;;
    stop) xo_afk_launch_stop ;;
    reconcile) xo_afk_launch_reconcile ;;
    -h|--help|help) xo_afk_launch_usage ;;
    *) xo_afk_launch_usage >&2; return 2 ;;
  esac
  result=$?
  xo_afk_launch_lock_release || result=1
  trap - EXIT INT TERM
  return "$result"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  xo_afk_launch_main "$@"
fi
