# shellcheck shell=bash
# xo-public-followup-lib.sh - shared gating and private-transport helpers for the
# deterministic public-followup consumer.
#
# XO promises a public final reply when a myfirstmate relay mention (X or
# Discord) asks for work. `tasks-axi public-followup` is the sole owner of that
# typed obligation and its state machine; state/x-context/ is the sole owner of
# the private full request context. This library owns XO's activation
# gate, private per-home transport paths, retained-loop state and locking
# helpers, follow-up window classification, and deterministic terminal-event
# identity.
#
# Sourced, never executed. No side effects on source (it creates nothing), which
# is what keeps a relay-disabled home free of public-followup artifacts.
# set -u / set -e safe.
#
# GATE ORDER - the acceptance criterion for relay-disabled homes:
#   1. xo_pf_relay_active <home>     the authoritative myfirstmate activation
#                                    contract, a non-empty XOX_PAIRING_TOKEN in
#                                    <home>/.env. There is no second flag. When
#                                    <home>/.env is absent this is a single
#                                    [ -f ] test and nothing else runs.
#   2. xo_pf_has_registrations       O(1) presence check on the registry created
#      / xo_pf_has_events            only by the relay path (xo-public-followup.sh
#      / xo_pf_has_open_loops        register). Open loops ARE registrations:
#                                    a delivered final keeps the record, so this
#                                    same check is the fail-loud session-start
#                                    gate. Relay-enabled homes with no public
#                                    loops stop here, so no tasks-axi call and
#                                    no backlog scan happens.
#
# Private transport layout, all under <home>/state/public-followup (mode 0700,
# initialized by `xo-public-followup.sh register` and extended only by these
# public-followup commands):
#   registry/<obligation-id>   registration record: the bounded private binding
#                              (obligation, relation, work ref and canonical
#                              secondmate path, generation, platform, request id)
#                              plus the loop fields that survive delivery (state,
#                              delivered_at, followup_expires_at,
#                              request_context_b64). Presence means the public
#                              loop is still open. Delivery
#                              stamps state=delivered; only `retire` removes the
#                              record. The obligation itself always remains
#                              tasks-axi truth.
#   events/<event-id>.json     inbound typed terminal events awaiting
#                              reconciliation, one file per event id.
#   outbox/<event-id>.json     OUTBOUND typed terminal events a worker in THIS
#                              home produced for an owning home on another
#                              machine, which no local path can reach. Same file
#                              shape as events/, staged here until that owning
#                              home collects them over the route's transport
#                              (bin/xo-public-followup-emit.sh --stage-in,
#                              bin/xo-public-followup-collect.sh). A home whose
#                              work is only ever local never has this directory.
#   consumed/<event-id>        idempotency ledger: an accepted event id is never
#                              replayed, so duplicate emits and restart replay
#                              are no-ops.
#   rejected/<event-id>.json   events tasks-axi refused, kept with a
#   rejected/<event-id>.reason one-line reason so a refusal is inspectable and
#                              never retried in a loop.
#   surfaced                   last surfaced pending-event signature, so the
#                              existing relay poll wakes once per new event set
#                              instead of every cycle.
#   retired/<obligation-id>    private retirement receipt containing the bounded
#                              reason and timestamp recorded before the registry
#                              entry is removed; its presence prevents replayed
#                              registration from reopening the closed loop.
#
# Event identity is DERIVED, never random: xo_pf_event_id hashes the canonical
# identity tuple, so re-emitting the same terminal result produces the same
# event id and the same destination path. Idempotency therefore holds across
# retries, restarts, and duplicate child reports without any coordination.
#
# Depends on bin/xo-x-lib.sh for .env reading and the private-artifact
# publication primitives (atomic, single-link, mode-validated, non-executable);
# those remain that file's contract and are not restated here.

_XO_PF_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)" || _XO_PF_LIB_DIR="."
# shellcheck source=bin/xo-x-lib.sh
. "$_XO_PF_LIB_DIR/xo-x-lib.sh"

XO_PF_DIRNAME='public-followup'
# Consumed by the sourcing scripts, not by this library.
# shellcheck disable=SC2034
XO_PF_EVENT_SCHEMA_VERSION=1
# Bounded so a public-safe outcome line can never carry a raw public message,
# and so one event file stays small enough to read and validate cheaply.
XO_PF_OUTCOME_TEXT_MAX=${XO_PF_OUTCOME_TEXT_MAX:-600}
XO_PF_EVENT_BYTES_MAX=${XO_PF_EVENT_BYTES_MAX:-8192}

# --- gate 1: the authoritative relay activation contract --------------------

# xo_pf_relay_active <home>: 0 when this home has opted into the myfirstmate
# relay, 1 otherwise. Identical contract to bootstrap's X-mode activation - a
# non-empty XOX_PAIRING_TOKEN in <home>/.env - so no second activation flag
# exists to drift. XOX_PAIRING_TOKEN in the environment wins, matching
# xox_load_config, so a direct client call and this gate agree.
xo_pf_relay_active() {
  local home=$1 token
  if [ -n "${XOX_PAIRING_TOKEN+x}" ]; then
    [ -n "${XOX_PAIRING_TOKEN-}" ]
    return $?
  fi
  [ -f "$home/.env" ] || return 1
  token=$(xox_env_get XOX_PAIRING_TOKEN "$home/.env")
  [ -n "$token" ]
}

# --- gate 2: O(1) presence checks on relay-path-owned registrations ---------

xo_pf_root()       { printf '%s\n' "$1/$XO_PF_DIRNAME"; }
xo_pf_registry_dir() { printf '%s\n' "$1/$XO_PF_DIRNAME/registry"; }
xo_pf_events_dir()   { printf '%s\n' "$1/$XO_PF_DIRNAME/events"; }
xo_pf_outbox_dir()   { printf '%s\n' "$1/$XO_PF_DIRNAME/outbox"; }
xo_pf_consumed_dir() { printf '%s\n' "$1/$XO_PF_DIRNAME/consumed"; }
xo_pf_rejected_dir() { printf '%s\n' "$1/$XO_PF_DIRNAME/rejected"; }
xo_pf_retired_dir()  { printf '%s\n' "$1/$XO_PF_DIRNAME/retired"; }

xo_pf_retirement_receipt_exists() {
  local file
  file="$(xo_pf_retired_dir "$1")/$2"
  [ -f "$file" ] && [ ! -L "$file" ]
}

# xo_pf_dir_has_entry <dir>: 0 when <dir> is a real directory holding at least
# one non-dot entry. Stops at the first hit, so cost does not grow with the
# directory's size.
xo_pf_dir_has_entry() {
  local dir=$1 entry
  [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
  for entry in "$dir"/*; do
    [ -e "$entry" ] || continue
    return 0
  done
  return 1
}

xo_pf_has_registrations() { xo_pf_dir_has_entry "$(xo_pf_registry_dir "$1")"; }
xo_pf_has_events()        { xo_pf_dir_has_entry "$(xo_pf_events_dir "$1")"; }
# Every retained registration is an open public loop (owed or delivered). Same
# O(1) directory presence check as xo_pf_has_registrations; the name is the
# post-retention semantic so callers do not treat "a reply is owed" as the
# only reason a record exists.
xo_pf_has_open_loops()    { xo_pf_has_registrations "$1"; }

# xo_pf_active <home> <state>: both gates, in order. The single predicate every
# caller outside the relay path should use before doing any public-followup work.
xo_pf_active() {
  xo_pf_relay_active "$1" || return 1
  xo_pf_has_registrations "$2" || xo_pf_has_events "$2"
}

# --- identifiers ------------------------------------------------------------

# xo_pf_slug_valid <value>: obligation ids, relation ids, work ids, and request
# ids all compose filenames. They arrive from tasks-axi, the relay, and child
# homes, so every one is checked against a conservative slug before use.
xo_pf_slug_valid() {
  local v=$1
  case "$v" in
    ''|.*|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#v}" -le 128 ]
}

# xo_pf_home_id_valid <home_id>: tasks-axi accepts "main" or
# "secondmate:<stable-id>" as a work_ref home. Validate the same shape here so a
# malformed source home is refused before it reaches a filename or a CLI call.
xo_pf_home_id_valid() {
  local v=$1
  case "$v" in
    main) return 0 ;;
    secondmate:*) xo_pf_slug_valid "${v#secondmate:}" ;;
    *) return 1 ;;
  esac
}

xo_pf_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum 2>/dev/null | awk '{print $1}'
  else
    return 1
  fi
}

# xo_pf_event_id <obligation> <relation> <source_home> <work_id> <generation>
#                <outcome_type> <deliverables-canonical>
# The stable idempotency identity. Derived from the identity tuple only, so the
# same terminal result always yields the same id no matter who emits it or how
# often. Public-safe outcome text is deliberately excluded: rewording the same
# landed outcome must not create a second event.
xo_pf_event_id() {
  printf '%s\037%s\037%s\037%s\037%s\037%s\037%s' "$1" "$2" "$3" "$4" "$5" "$6" "$7" \
    | xo_pf_sha256
}

# --- bounded public-safe text ----------------------------------------------

# xo_pf_clean_outcome_text: read stdin, drop control characters, collapse every
# whitespace run to a single space, and trim. An event line therefore stays
# single-line and a raw pasted public message cannot ride along inside it.
# Deliberately does NOT truncate: a byte-wise cut would split a multi-byte
# character, so length bounding happens where it can count codepoints - jq, at
# the point the typed event is built.
xo_pf_clean_outcome_text() {
  LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' \
    | LC_ALL=C tr '\011\012\015' '   ' \
    | LC_ALL=C tr -s ' ' \
    | sed 's/^ //; s/ $//'
}

# xo_pf_bound_bytes <max>: hard byte cap for text that never becomes JSON, such
# as a quarantined event's one-line refusal reason.
xo_pf_bound_bytes() {
  LC_ALL=C cut -b "1-$1"
}

# --- registry records -------------------------------------------------------

# xo_pf_registry_get <state> <obligation-id> <key>: read one key=value line from
# a registration record. Prints nothing and succeeds when absent.
xo_pf_registry_get() {
  local state=$1 id=$2 key=$3 file line
  xo_pf_slug_valid "$id" || return 1
  file="$(xo_pf_registry_dir "$state")/$id"
  [ -f "$file" ] && [ ! -L "$file" ] || return 0
  line=$(grep -E "^${key}=" "$file" 2>/dev/null | tail -n1) || return 0
  printf '%s' "${line#*=}"
}

# xo_pf_registry_ids <state>: every registered obligation id, one per line.
# The registry only ever holds this home's live public commitments, so this stays
# a bounded listing rather than a backlog scan.
xo_pf_registry_ids() {
  local dir entry
  dir=$(xo_pf_registry_dir "$1")
  [ -d "$dir" ] && [ ! -L "$dir" ] || return 0
  for entry in "$dir"/*; do
    [ -f "$entry" ] && [ ! -L "$entry" ] || continue
    basename "$entry"
  done
}

# xo_pf_registry_ids_for_work <state> <work_home_id> <work_id>: the obligations
# this home registered against one exact work relation. Used by the completion
# guard so cleanup cannot declare bound work finished while its public promise is
# still open.
xo_pf_registry_ids_for_work() {
  local state=$1 home_id=$2 work_id=$3 id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    [ "$(xo_pf_registry_get "$state" "$id" work_home)" = "$home_id" ] || continue
    [ "$(xo_pf_registry_get "$state" "$id" work_id)" = "$work_id" ] || continue
    printf '%s\n' "$id"
  done <<EOF
$(xo_pf_registry_ids "$state")
EOF
}

# xo_pf_now_epoch: wall clock as epoch seconds. XOX_NOW_OVERRIDE pins it for
# tests, matching bin/xo-x-lib.sh.
xo_pf_now_epoch() {
  printf '%s\n' "${XOX_NOW_OVERRIDE:-$(date +%s)}"
}

# xo_pf_now_rfc3339: UTC timestamp for delivered_at and similar stamps.
xo_pf_now_rfc3339() {
  local epoch
  epoch=$(xo_pf_now_epoch)
  date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u +%Y-%m-%dT%H:%M:%SZ
}

# xo_pf_rfc3339_to_epoch <rfc3339>: parse a Zulu timestamp. Empty on failure.
xo_pf_rfc3339_to_epoch() {
  local ts=$1
  [ -n "$ts" ] || return 1
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null \
    || date -u -d "$ts" +%s 2>/dev/null \
    || return 1
}

# xo_pf_followup_window_class <rfc3339>: ok, closing (<48h), expired, or unknown.
xo_pf_followup_window_class() {
  local ts=$1 exp now
  exp=$(xo_pf_rfc3339_to_epoch "$ts") || { printf 'unknown\n'; return 0; }
  now=$(xo_pf_now_epoch)
  if [ "$now" -ge "$exp" ]; then
    printf 'expired\n'
  elif [ $((exp - now)) -lt 172800 ]; then
    printf 'closing\n'
  else
    printf 'ok\n'
  fi
}

# xo_pf_b64_encode: stdin to a single-line base64 payload (no wrapping).
xo_pf_b64_encode() {
  base64 2>/dev/null | tr -d '\n\r'
}

# xo_pf_b64_decode: stdin (single-line or wrapped base64) to bytes on stdout.
xo_pf_b64_decode() {
  local data
  data=$(cat)
  printf '%s\n' "$data" | base64 -d 2>/dev/null \
    || printf '%s\n' "$data" | base64 -D 2>/dev/null
}

# xo_pf_registry_loop_state <state> <id>: open or delivered. A pre-change
# record with no state= is treated as open so live homes never crash.
xo_pf_registry_loop_state() {
  local v
  v=$(xo_pf_registry_get "$1" "$2" state)
  case "$v" in
    delivered) printf 'delivered\n' ;;
    *) printf 'open\n' ;;
  esac
}

# xo_pf_registry_rechainable <state> <id>: 0 when request_context_b64 is present.
xo_pf_registry_rechainable() {
  local ctx
  ctx=$(xo_pf_registry_get "$1" "$2" request_context_b64)
  [ -n "$ctx" ]
}

# xo_pf_has_delivered_open_loops <state>: 0 when any retained record is
# state=delivered (an open loop with nothing owed). Pre-change records have no
# state= and are treated as still-owed, not delivered.
xo_pf_has_delivered_open_loops() {
  local state=$1 id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    [ "$(xo_pf_registry_get "$state" "$id" state)" = delivered ] || continue
    return 0
  done <<EOF
$(xo_pf_registry_ids "$state")
EOF
  return 1
}

xo_pf_registry_lock_path() {
  printf '%s/.registry-%s.lock\n' "$(xo_pf_root "$1")" "$2"
}

xo_pf_registry_lock_acquire() {
  local state=$1 id=$2
  xo_pf_slug_valid "$id" || return 1
  xox_private_artifact_dir_prepare "$(xo_pf_root "$state")" >/dev/null || return 1
  if ! command -v xo_lock_acquire_wait >/dev/null 2>&1; then
    # shellcheck source=bin/xo-wake-lib.sh
    . "$_XO_PF_LIB_DIR/xo-wake-lib.sh"
  fi
  xo_lock_acquire_wait "$(xo_pf_registry_lock_path "$state" "$id")"
}

xo_pf_registry_lock_release() {
  xo_lock_release "$(xo_pf_registry_lock_path "$1" "$2")"
}

# xo_pf_registry_stamp_delivered <state> <id> <rfc3339>: rewrite one record
# with state=delivered and delivered_at, keeping every other field. The record
# stays; only retire removes it.
xo_pf_registry_stamp_delivered() {
  local state=$1 id=$2 delivered_at=$3 file rest rc=0
  xo_pf_slug_valid "$id" || return 1
  [ -n "$delivered_at" ] || return 1
  xo_pf_registry_lock_acquire "$state" "$id" || return 1
  file="$(xo_pf_registry_dir "$state")/$id"
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    rest=$(grep -v -E '^(state|delivered_at|delivered_obligation)=' "$file" 2>/dev/null || true)
    printf '%s\nstate=delivered\ndelivered_at=%s\ndelivered_obligation=%s\n' \
      "$rest" "$delivered_at" "$id" \
      | xox_private_artifact_publish_stdin "$(xo_pf_registry_dir "$state")" "$id" 600 \
      || rc=$?
  else
    rc=3
  fi
  xo_pf_registry_lock_release "$state" "$id"
  return "$rc"
}

# --- pending-event signature ------------------------------------------------

# Consumed by the sourcing scripts, not by this library.
# shellcheck disable=SC2034
XO_PF_SURFACED_BASENAME=surfaced

# xo_pf_events_signature <state>: a stable digest of the pending event id set.
# The relay poll compares it against the surfaced record so an unconsumed event
# wakes xo once per new event, not once per poll cycle.
xo_pf_events_signature() {
  local dir entry pending_names=
  dir=$(xo_pf_events_dir "$1")
  [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
  for entry in "$dir"/*.json; do
    [ -f "$entry" ] && [ ! -L "$entry" ] || continue
    pending_names="$pending_names$(basename "$entry")
"
  done
  [ -n "$pending_names" ] || return 1
  printf '%s' "$pending_names" | LC_ALL=C sort | xo_pf_sha256
}
