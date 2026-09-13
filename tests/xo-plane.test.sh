#!/usr/bin/env bash
# Offline Plane adapter behavior: real Git contention, lifecycle and MCP transport.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
"${XO_PLANE_PYTHON:-python3}" "$ROOT/tests/xo_plane_test.py"
