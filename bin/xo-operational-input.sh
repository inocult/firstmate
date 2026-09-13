#!/usr/bin/env bash
# xo-operational-input.sh - canonical XO operational-input protocol.
#
# This file is both a source-safe shell library and the cross-language CLI used
# by JavaScript and TypeScript integrations. It is the single owner of current
# construction, current parsing, and narrow pre-protocol transcript parsing.
#
# Current generic wire form:
#   U+2063 XO_OP: v1 <kind>: <body>
#
# The landed U+2063 + "XO_OP: " prefix is permanent compatibility.
# The version and kind header make current inputs structurally typed without
# deriving provenance from body prose. The established from-primary routing
# marker remains a current compatibility carrier because already-running
# secondmates have its leading label in their charter context.
#
# CLI:
#   xo-operational-input.sh encode <kind>  # body on stdin, encoded input stdout
#   xo-operational-input.sh kind           # current input on stdin, kind stdout
#   xo-operational-input.sh classify       # current or legacy input on stdin
#   xo-operational-input.sh body           # current generic input on stdin
#   xo-operational-input.sh --help
#
# All successful data commands print exactly one value and no diagnostics.
# A non-match exits 1 silently. Invalid use exits 2. Bash 3.2 compatible.

XO_OPERATIONAL_MARK=$'\xE2\x81\xA3'
XO_OPERATIONAL_PREFIX="${XO_OPERATIONAL_MARK}XO_OP: "
XO_OPERATIONAL_VERSION=v1
XO_OPERATIONAL_HEADER_PREFIX="${XO_OPERATIONAL_PREFIX}${XO_OPERATIONAL_VERSION} "
XO_OPERATIONAL_KINDS='session-start watcher turn-end-guard away-supervisor launch-brief branch-outcome'

# Compatibility name retained for the away-mode owner and its tests.
# shellcheck disable=SC2034 # Public source-library variable used by callers.
XO_INJECT_MARK=$XO_OPERATIONAL_MARK

# The from-primary carrier stays byte-compatible with live secondmate charter
# context while this owner supplies its construction and structural kind.
XO_FROMPRIMARY_LABEL='[xo-from-primary]'
XO_FROMPRIMARY_SEPARATOR=$XO_OPERATIONAL_MARK
XO_FROMPRIMARY_MARK="${XO_FROMPRIMARY_LABEL}${XO_FROMPRIMARY_SEPARATOR}"

xo_operational_kind_is_current() {  # <kind>
  case " $XO_OPERATIONAL_KINDS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

xo_operational_input_encode() {  # <generic-kind> <body> <result-var>
  local kind=${1-} body=${2-} result_var=${3-}
  [ -n "$result_var" ] || return 2
  xo_operational_kind_is_current "$kind" || return 2
  [ -n "$body" ] || return 2
  printf -v "$result_var" '%s%s: %s' "$XO_OPERATIONAL_HEADER_PREFIX" "$kind" "$body"
}

xo_operational_input_construct() {  # <kind> <body> <result-var>
  local kind=${1-} body=${2-} result_var=${3-}
  [ -n "$result_var" ] && [ -n "$body" ] || return 2
  if [ "$kind" = from-primary ]; then
    xo_message_mark_from_xo "$body" "$result_var"
    return
  fi
  xo_operational_input_encode "$kind" "$body" "$result_var"
}

xo_operational_generic_kind() {  # <message> <result-var>
  local message=${1-} result_var=${2-} remainder parsed_kind body
  [ -n "$result_var" ] || return 2
  case "$message" in
    "$XO_OPERATIONAL_HEADER_PREFIX"*': '?*) ;;
    *) return 1 ;;
  esac
  remainder=${message#"$XO_OPERATIONAL_HEADER_PREFIX"}
  parsed_kind=${remainder%%': '*}
  xo_operational_kind_is_current "$parsed_kind" || return 1
  body=${remainder#"${parsed_kind}: "}
  [ "$body" != "$remainder" ] && [ -n "$body" ] || return 1
  printf -v "$result_var" '%s' "$parsed_kind"
}

xo_operational_input_kind() {  # <message> <result-var>
  local message=${1-} result_var=${2-} current_kind
  [ -n "$result_var" ] || return 2
  if xo_operational_generic_kind "$message" current_kind; then
    printf -v "$result_var" '%s' "$current_kind"
    return 0
  fi
  case "$message" in
    "$XO_FROMPRIMARY_MARK"?*)
      printf -v "$result_var" '%s' from-primary
      return 0
      ;;
  esac
  return 1
}

xo_operational_input_body() {  # <current-message> <result-var>
  local message=${1-} result_var=${2-} current_kind parsed_body
  [ -n "$result_var" ] || return 2
  if xo_operational_generic_kind "$message" current_kind; then
    parsed_body=${message#"${XO_OPERATIONAL_HEADER_PREFIX}${current_kind}: "}
    printf -v "$result_var" '%s' "$parsed_body"
    return 0
  fi
  case "$message" in
    "$XO_FROMPRIMARY_MARK"?*)
      parsed_body=${message#"$XO_FROMPRIMARY_MARK"}
      printf -v "$result_var" '%s' "$parsed_body"
      return 0
      ;;
  esac
  return 1
}

# Historical payload literals are intentionally isolated below this line.
# They exist only for persisted pre-protocol transcripts and must never be used
# by current producers or current-path tests.
# shellcheck disable=SC2016 # Backticks are literal historical prompt markup.
XO_LEGACY_SESSIONSTART='Run `bin/xo-session-start.sh` now, exactly once, before executing any other instructions.'
XO_LEGACY_WATCHER_PREFIX='XO WATCHER WAKE: '
XO_LEGACY_WATCHER_SUFFIX=$'\n\nRun bin/xo-wake-drain.sh first and handle the queued wake. Watcher continuity is extension-owned.'
XO_LEGACY_TURNEND_PREFIX=$'TURN WOULD END BLIND - supervision is off. The watcher cycle is missing, failed, or unhealthy. Follow the harness recovery instruction below before ending the turn.\n\n'
XO_LEGACY_AWAY_PREFIX="${XO_OPERATIONAL_MARK}Supervisor escalate ("

xo_legacy_operational_input_kind() {  # <message> <result-var>
  local message=${1-} result_var=${2-}
  [ -n "$result_var" ] || return 2

  # PR 899 landed an untyped XO_OP prefix. Its subtype cannot be
  # recovered without body prose, so it is explicitly generic.
  case "$message" in
    "$XO_OPERATIONAL_PREFIX"?*)
      printf -v "$result_var" '%s' legacy-operational
      return 0
      ;;
  esac

  if [ "$message" = "$XO_LEGACY_SESSIONSTART" ]; then
    printf -v "$result_var" '%s' session-start
    return 0
  fi
  case "$message" in
    "$XO_LEGACY_AWAY_PREFIX"*)
      printf -v "$result_var" '%s' away-supervisor
      return 0
      ;;
    "$XO_LEGACY_WATCHER_PREFIX"*"$XO_LEGACY_WATCHER_SUFFIX")
      [ "${#message}" -gt "$(( ${#XO_LEGACY_WATCHER_PREFIX} + ${#XO_LEGACY_WATCHER_SUFFIX} ))" ] || return 1
      printf -v "$result_var" '%s' watcher
      return 0
      ;;
    "$XO_LEGACY_TURNEND_PREFIX"?*)
      printf -v "$result_var" '%s' turn-end-guard
      return 0
      ;;
  esac
  return 1
}

xo_operational_input_classify() {  # <message> <result-var>
  local message=${1-} result_var=${2-} classified_kind
  [ -n "$result_var" ] || return 2
  if xo_operational_input_kind "$message" classified_kind ||
     xo_legacy_operational_input_kind "$message" classified_kind; then
    printf -v "$result_var" '%s' "$classified_kind"
    return 0
  fi
  return 1
}

xo_message_from_xo() {  # <message>
  local kind
  xo_operational_input_kind "${1-}" kind && [ "$kind" = from-primary ]
}

xo_message_mark_from_xo() {  # <message> <result-var>
  local message=${1-} result_var=${2-} transformed
  [ -n "$result_var" ] || return 2
  if xo_message_from_xo "$message"; then
    transformed=$message
  else
    transformed="${XO_FROMPRIMARY_MARK}${message}"
  fi
  printf -v "$result_var" '%s' "$transformed"
}

xo_operational_read_stdin() {  # <result-var>
  local result_var=${1-} value
  [ -n "$result_var" ] || return 2
  value=$(cat; printf x)
  value=${value%x}
  printf -v "$result_var" '%s' "$value"
}

xo_operational_usage() {
  cat <<'EOF'
Usage:
  bin/xo-operational-input.sh encode <kind>  # body on stdin
  bin/xo-operational-input.sh kind           # current input on stdin
  bin/xo-operational-input.sh classify       # current or legacy input on stdin
  bin/xo-operational-input.sh body           # current input on stdin

Current construction kinds:
  session-start watcher turn-end-guard away-supervisor from-primary launch-brief
  branch-outcome

The from-primary kind uses its established live-charter-compatible carrier.
EOF
}

xo_operational_main() {
  local command=${1-} argument=${2-} input output
  case "$command" in
    -h|--help|help)
      xo_operational_usage
      ;;
    encode)
      [ "$#" -eq 2 ] || return 2
      xo_operational_read_stdin input || return 2
      xo_operational_input_construct "$argument" "$input" output || return 2
      printf '%s' "$output"
      ;;
    kind)
      [ "$#" -eq 1 ] || return 2
      xo_operational_read_stdin input || return 2
      xo_operational_input_kind "$input" output || return 1
      printf '%s\n' "$output"
      ;;
    classify)
      [ "$#" -eq 1 ] || return 2
      xo_operational_read_stdin input || return 2
      xo_operational_input_classify "$input" output || return 1
      printf '%s\n' "$output"
      ;;
    body)
      [ "$#" -eq 1 ] || return 2
      xo_operational_read_stdin input || return 2
      xo_operational_input_body "$input" output || return 1
      printf '%s' "$output"
      ;;
    *)
      xo_operational_usage >&2
      return 2
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  xo_operational_main "$@"
  exit $?
fi
