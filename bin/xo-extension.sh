#!/usr/bin/env bash
# Tracked shell entrypoint for local and xo-on extension binding commands.
set -eu
set -o pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
if [ "${1:-}" = remote-bind ]; then
  [ "$#" -ge 4 ] || { printf 'usage: %s remote-bind <secondmate-id> <package-root> <bind-options...>\n' "$0" >&2; exit 2; }
  route=$2
  package_root=$3
  shift 3
  "$SCRIPT_DIR/xo-extension.mjs" pack-transfer "$package_root" \
    | "$SCRIPT_DIR/xo-on.sh" --stdin "$route" xo-extension.sh receive-transfer-bind "$@"
  exit $?
fi
exec "$SCRIPT_DIR/xo-extension.mjs" "$@"
