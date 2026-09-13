#!/usr/bin/env bash
# Acquire or inspect the per-home xo session lock.
# Writes the harness (agent) process PID found by walking the shell's ancestry,
# which lives as long as the xo session - unlike the transient subshell
# PID of any one tool call, which is dead moments after it is written.
# Usage: xo-lock.sh           acquire; exit 1 unless ownership is verified
#        xo-lock.sh status    print holder and liveness; always exits 0
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XO_ROOT="${XO_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
XO_HOME="${XO_HOME:-${XO_ROOT_OVERRIDE:-$XO_ROOT}}"
STATE="${XO_STATE_OVERRIDE:-$XO_HOME/state}"
LOCK="$STATE/.lock"
mkdir -p "$STATE" 2>/dev/null || {
  echo "error: cannot create session-lock state directory $STATE; operate read-only until resolved" >&2
  exit 1
}

# Harness identity (XO_HARNESS_RE, ancestry walk, holder liveness) is owned by
# the shared session-lock lib so the Claude Stop auto-arm applies the exact
# same identity contract.
# shellcheck source=bin/xo-session-lock-lib.sh
. "$SCRIPT_DIR/xo-session-lock-lib.sh"

if [ "${1:-}" = "status" ]; then
  if [ ! -f "$LOCK" ]; then echo "lock: free"; exit 0; fi
  old=$(cat "$LOCK" 2>/dev/null) || {
    echo "lock: unreadable"
    exit 0
  }
  if xo_harness_pid_alive "$old"; then echo "lock: held by live harness pid $old"; else echo "lock: stale (pid $old dead or not a harness)"; fi
  exit 0
fi

me=$(xo_harness_ancestry_pid) || { echo "error: cannot locate harness process in ancestry" >&2; exit 1; }
probe=$(mktemp "$STATE/.lock-write.XXXXXX" 2>/dev/null) || {
  echo "error: cannot write session lock; operate read-only until resolved" >&2
  exit 1
}
rm -f "$probe" 2>/dev/null || {
  echo "error: cannot clean session-lock publication probe; operate read-only until resolved" >&2
  exit 1
}
# shellcheck source=bin/xo-wake-lib.sh
. "$SCRIPT_DIR/xo-wake-lib.sh"
CLAIM_LOCK="$STATE/.lock.acquire"
CLAIM_LOCK_HELD=0
release_claim_lock() {
  if [ "$CLAIM_LOCK_HELD" -eq 1 ]; then
    xo_lock_release "$CLAIM_LOCK"
    CLAIM_LOCK_HELD=0
  fi
}
trap release_claim_lock EXIT
trap 'exit 1' HUP INT TERM

if [ -f "$LOCK" ] && [ ! -L "$LOCK" ]; then
  old=$(cat "$LOCK" 2>/dev/null || true)
  if [ "$old" = "$me" ]; then
    echo "lock acquired: harness pid $me"
    exit 0
  fi
  if xo_harness_pid_alive "$old"; then
    echo "error: another live xo session holds the lock (pid $old); operate read-only until resolved" >&2
    exit 1
  fi
fi

if ! xo_lock_try_acquire "$CLAIM_LOCK"; then
  sweep_pid=$(sed -n 's/^pid=//p' "$STATE/.startup-network.status" 2>/dev/null | tail -1)
  if [ -n "${XO_LOCK_HELD_PID:-}" ] && [ "$XO_LOCK_HELD_PID" = "$sweep_pid" ]; then
    echo "error: the prior session's bounded startup sweep is finishing; operate read-only until it releases the fleet lock" >&2
    exit 1
  fi
  xo_lock_acquire_wait "$CLAIM_LOCK"
fi
CLAIM_LOCK_HELD=1

if [ -e "$LOCK" ] || [ -L "$LOCK" ]; then
  if [ ! -f "$LOCK" ] || [ -L "$LOCK" ]; then
    echo "error: session lock is not a regular file; operate read-only until resolved" >&2
    exit 1
  fi
  old=$(cat "$LOCK" 2>/dev/null) || {
    echo "error: session lock is unreadable; operate read-only until resolved" >&2
    exit 1
  }
  if [ "$old" != "$me" ] && xo_harness_pid_alive "$old"; then
    echo "error: another live xo session holds the lock (pid $old); operate read-only until resolved" >&2
    exit 1
  fi
fi
if ! { printf '%s\n' "$me" > "$LOCK"; } 2>/dev/null; then
  echo "error: cannot write session lock; operate read-only until resolved" >&2
  exit 1
fi
written=$(cat "$LOCK" 2>/dev/null) || {
  echo "error: cannot verify session lock ownership; operate read-only until resolved" >&2
  exit 1
}
if [ ! -f "$LOCK" ] || [ -L "$LOCK" ] || [ "$written" != "$me" ]; then
  echo "error: session lock ownership verification failed; operate read-only until resolved" >&2
  exit 1
fi
release_claim_lock
echo "lock acquired: harness pid $me"
