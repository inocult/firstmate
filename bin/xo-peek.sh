#!/usr/bin/env bash
# Print the tail of a crewmate endpoint (bounded, for cheap diagnosis).
# Usage: xo-peek.sh <target> [lines=40]
#   <target> may be an exact task id, a legacy xo-<id> task label resolved
#   through this home's state/<id>.meta, or an explicit backend target.
# A selector whose meta records remote_host= is a remote secondmate: its pane
# lives on that host, so the capture routes over xo-on.sh to the host-local
# capture (xo-remote-secondmate-control.sh), clamped to that command's
# 100-line cap. An unreachable host or unreadable endpoint fails loudly naming
# the host; the local backend adapters are never asked to read a remote target.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XO_ROOT="${XO_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
XO_HOME="${XO_HOME:-${XO_ROOT_OVERRIDE:-$XO_ROOT}}"
STATE="${XO_STATE_OVERRIDE:-$XO_HOME/state}"

# shellcheck source=bin/xo-backend.sh
. "$SCRIPT_DIR/xo-backend.sh"

"$SCRIPT_DIR/xo-guard.sh" || true

RAW_TARGET=$1
N=${2:-40}

REMOTE_META=$(xo_backend_meta_for_selector "$RAW_TARGET" "$STATE" 2>/dev/null || true)
if [ -n "$REMOTE_META" ] && [ -n "$(xo_meta_get "$REMOTE_META" remote_host)" ]; then
  REMOTE_ID=${REMOTE_META##*/}
  REMOTE_ID=${REMOTE_ID%.meta}
  REMOTE_HOST=$(xo_meta_get "$REMOTE_META" remote_host)
  case "$N" in ''|*[!0-9]*|0) N=40 ;; esac
  [ "$N" -le 100 ] || N=100
  if ! XO_HOME="$XO_HOME" "$SCRIPT_DIR/xo-on.sh" "$REMOTE_ID" \
    xo-remote-secondmate-control.sh capture "$REMOTE_ID" "$N" < /dev/null; then
    echo "error: could not read the remote pane of $REMOTE_ID on $REMOTE_HOST (host unreachable or endpoint unreadable; the mate is not thereby dead)" >&2
    exit 1
  fi
  exit 0
fi

T=$(xo_backend_resolve_selector "$RAW_TARGET" "$STATE")

BACKEND=$(xo_backend_of_selector "$RAW_TARGET" "$T" "$STATE")
EXPECTED_LABEL=$(xo_backend_expected_label_of_selector "$RAW_TARGET" "$STATE")

xo_backend_capture "$BACKEND" "$T" "$N" "$EXPECTED_LABEL"
