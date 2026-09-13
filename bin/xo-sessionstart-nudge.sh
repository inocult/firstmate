#!/usr/bin/env bash
# Print the one-line session-start instruction only for a genuine xo
# primary whose current harness session has not already acquired the home lock.
# Every silence and error path exits 0 because Claude SessionStart exit 2 blocks
# session initialization.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XO_ROOT="${XO_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
XO_HOME="${XO_HOME:-${XO_ROOT_OVERRIDE:-$XO_ROOT}}"
STATE="${XO_STATE_OVERRIDE:-$XO_HOME/state}"

# shellcheck source=bin/xo-gate-refuse-lib.sh
. "$SCRIPT_DIR/xo-gate-refuse-lib.sh"
# shellcheck source=bin/xo-primary-scope-lib.sh
. "$SCRIPT_DIR/xo-primary-scope-lib.sh"
# shellcheck source=bin/xo-operational-input.sh
. "$SCRIPT_DIR/xo-operational-input.sh"

xo_is_gate_agent "$XO_ROOT" && exit 0
xo_primary_scope_matches "$XO_ROOT" "$STATE" || exit 0

lock_is_in_ancestry() {
  local lock_pid pid=$$ _
  [ -f "$STATE/.lock" ] || return 1
  IFS= read -r lock_pid < "$STATE/.lock" 2>/dev/null || return 1
  case "$lock_pid" in
    ''|*[!0-9]*|1) return 1 ;;
  esac
  kill -0 "$lock_pid" 2>/dev/null || return 1
  for _ in 1 2 3 4 5 6 7 8; do
    [ "$pid" = "$lock_pid" ] && return 0
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$pid" ] && [ "$pid" -gt 1 ] || return 1
  done
  return 1
}

lock_is_in_ancestry && exit 0
nudge=
xo_operational_input_encode session-start \
  "Run \`bin/xo-session-start.sh\` now, exactly once, before executing any other instructions." \
  nudge || exit 0
printf '%s\n' "$nudge"
exit 0
