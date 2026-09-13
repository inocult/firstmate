#!/usr/bin/env bash
# xo-marker-lib.sh - compatibility entry point for from-primary routing.
#
# bin/xo-operational-input.sh owns current operational-input construction,
# parsing, marker bytes, and the established from-primary compatibility
# carrier. Existing callers source this path so they do not need a flag-day
# migration. No side effects on source. set -u / set -e safe.

_XO_MARKER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/xo-operational-input.sh
. "$_XO_MARKER_LIB_DIR/xo-operational-input.sh"
unset _XO_MARKER_LIB_DIR
