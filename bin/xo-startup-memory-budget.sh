#!/usr/bin/env bash
# Read and account for the local startup-memory budget.
# Usage:
#   xo-startup-memory-budget.sh read
#   xo-startup-memory-budget.sh report
#
# `read` prints the one validated effective budget from
# config/startup-memory-budget.  `report` prints the stable local estimate for
# data/captain.md, data/captain-shared.md, and data/learnings.md together.
# Bootstrap owns default materialization; this command never creates or repairs
# configuration, so an absent, malformed, symlinked, hardlinked, or otherwise
# unsafe value is a concrete error rather than an inferred default.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XO_ROOT="${XO_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
XO_HOME="${XO_HOME:-${XO_ROOT_OVERRIDE:-$XO_ROOT}}"
CONFIG="${XO_CONFIG_OVERRIDE:-$XO_HOME/config}"
DATA="${XO_DATA_OVERRIDE:-$XO_HOME/data}"

# shellcheck source=bin/xo-startup-memory-budget-lib.sh
. "$SCRIPT_DIR/xo-startup-memory-budget-lib.sh"

usage() {
  sed -n '2,11{s/^# \{0,1\}//;p;}' "$0"
}

print_error() {
  printf 'startup-memory-budget: %s\n' "$1" >&2
}

read_budget() {
  if ! xo_startup_memory_budget_read "$CONFIG" >/dev/null; then
    print_error "invalid config/$XO_STARTUP_MEMORY_BUDGET_FILE - $XO_STARTUP_MEMORY_BUDGET_ERROR"
    return 1
  fi
  printf '%s\n' "$XO_STARTUP_MEMORY_BUDGET_VALUE"
}

report() {
  local budget bytes tokens presence total=0 shared_tokens=0 role=primary
  if ! budget=$(read_budget); then
    return 2
  fi

  if [ -e "$XO_HOME/.xo-secondmate-home" ] || [ -L "$XO_HOME/.xo-secondmate-home" ]; then
    role=secondmate
  fi

  printf 'estimator=ceil(UTF-8 bytes / 3) conservative-local-estimate\n'
  printf 'role=%s\n' "$role"
  printf 'effective_budget_tokens=%s\n' "$budget"
  for file in captain.md captain-shared.md learnings.md; do
    if ! xo_startup_memory_measure_file "$DATA/$file" >/dev/null; then
      print_error "$XO_STARTUP_MEMORY_BUDGET_ERROR"
      return 2
    fi
    bytes=$XO_STARTUP_MEMORY_MEASURE_BYTES
    tokens=$XO_STARTUP_MEMORY_MEASURE_TOKENS
    presence=$XO_STARTUP_MEMORY_MEASURE_PRESENCE
    total=$((total + tokens))
    [ "$file" != captain-shared.md ] || shared_tokens=$tokens
    printf 'file=data/%s bytes=%s estimated_tokens=%s status=%s\n' \
      "$file" "$bytes" "$tokens" "$presence"
  done
  printf 'total_estimated_tokens=%s\n' "$total"
  if xo_startup_memory_decimal_le "$total" "$budget"; then
    printf 'budget_status=within-budget\n'
  else
    printf 'budget_status=over-budget\n'
  fi
  if [ "$role" = secondmate ] \
    && ! xo_startup_memory_decimal_le "$shared_tokens" "$budget"; then
    printf 'exception=primary-owned-shared-file-alone-exceeds-budget\n'
  fi
}

case "${1:-}" in
  read)
    [ "$#" -eq 1 ] || { usage >&2; exit 2; }
    read_budget
    ;;
  report)
    [ "$#" -eq 1 ] || { usage >&2; exit 2; }
    report
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
