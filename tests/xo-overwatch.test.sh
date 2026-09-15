#!/usr/bin/env bash
# Overwatch holds local pickup policy only: bounds, cadence, watcher
# registration and a scope recorded from the minimal tracker binding.
#
# It never reaches the tracker, so these cases run with no connector and no
# credentials: every assertion below is about the durable policy record, the
# registered check's output and the binding validation that guards enabling.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOME_DIR=$(xo_test_tmproot xo-overwatch-home) || exit 1
BINDING="$HOME_DIR/config/plane.json"
mkdir -p "$HOME_DIR/config"

write_binding() {  # [project_id]
  cat > "$BINDING" <<JSON
{
  "workspace_slug": "at-bryde-ud",
  "project_id": "${1:-project-uuid-1}",
  "project_identifier": "PLAT"
}
JSON
}

overwatch() {  # <expected exit> <args...>
  local expected=$1 status=0
  shift
  OVERWATCH_OUT=$(XO_HOME="$HOME_DIR" XO_STATE_OVERRIDE="$HOME_DIR/state" \
    python3 "$ROOT/bin/xo-overwatch.py" "$@" 2>"$HOME_DIR/stderr") || status=$?
  expect_code "$expected" "$status" "xo-overwatch.py $*"
}

policy_field() {  # <field>
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' \
    "$HOME_DIR/state/overwatch.json" "$1"
}

test_disabled_by_default_and_silent() {
  overwatch 0 status
  assert_contains "$OVERWATCH_OUT" '"enabled": false' "a fresh home reports Overwatch disabled"
  overwatch 0 check
  assert_equals "" "$OVERWATCH_OUT" "a disabled Overwatch prints no wake line"
  pass "Overwatch is disabled by default and its check stays silent"
}

test_enabling_records_scope_and_registers_the_check() {
  write_binding
  overwatch 0 on
  assert_contains "$OVERWATCH_OUT" '"enabled": true' "on enables the policy"
  assert_equals project-uuid-1 "$(policy_field project_id)" "the policy records the bound project"
  assert_equals PLAT "$(policy_field project_identifier)" "the policy records the project identifier"
  assert_equals at-bryde-ud "$(policy_field workspace_slug)" "the policy records the bound workspace"
  assert_present "$HOME_DIR/state/overwatch.check.sh" "enabling writes the registered check"
  bash -c '. "$1"; . "$2"; xo_custom_check_registered "$3" overwatch' test \
    "$ROOT/bin/xo-pr-lib.sh" "$ROOT/bin/xo-check-lib.sh" "$HOME_DIR/state" \
    || fail "enabling must register the Overwatch check with the watcher"
  pass "enabling records the bound scope and registers the watcher check"
}

test_the_check_repeats_until_an_outcome_is_recorded() {
  overwatch 0 check
  assert_contains "$OVERWATCH_OUT" "pickup check due" "a due check wakes XO"
  overwatch 0 check
  assert_contains "$OVERWATCH_OUT" "pickup check due" "the wake repeats until XO records an outcome"
  pass "the registered check keeps emitting a due wake until an outcome lands"
}

test_empty_outcomes_back_off_and_the_budget_stops_pickup() {
  overwatch 0 defer --outcome empty
  assert_contains "$OVERWATCH_OUT" '"empty_streak": 1' "an empty outcome extends the backoff"
  overwatch 0 check
  assert_equals "" "$OVERWATCH_OUT" "a backed-off Overwatch stays silent until its next check is due"
  overwatch 0 defer --outcome picked
  assert_equals 0 "$(policy_field empty_streak)" "a pickup clears the empty streak"
  pass "empty outcomes back the timer off and a pickup clears the streak"
}

test_the_pickup_budget_stops_new_intake() {
  overwatch 0 off
  overwatch 0 on --max-pickups 1
  overwatch 0 defer --outcome picked
  overwatch 0 check
  assert_contains "$OVERWATCH_OUT" "pickup budget reached" "a spent budget stops new intake"
  pass "the pickup budget stops new intake and asks for a deliberate decision"
}

test_a_changed_binding_pauses_pickup() {
  write_binding project-uuid-2
  overwatch 0 check
  assert_contains "$OVERWATCH_OUT" "tracker binding changed" "a rebound project pauses pickup"
  pass "a changed tracker binding pauses pickup instead of claiming under the old scope"
}

test_off_retires_the_check_and_preserves_work() {
  local preserved="$HOME_DIR/state/mission.json"
  printf 'active work\n' > "$preserved"
  overwatch 0 off
  assert_absent "$HOME_DIR/state/overwatch.check.sh" "off retires the registered check"
  overwatch 0 check
  assert_equals "" "$OVERWATCH_OUT" "a retired Overwatch prints no wake line"
  assert_equals "active work" "$(cat "$preserved")" "off preserves existing work records"
  pass "off retires the check and leaves existing work untouched"
}

test_bounds_and_double_enable_are_refused() {
  write_binding
  overwatch 1 on --interval 0
  overwatch 1 on --slots 0
  overwatch 1 on --max-pickups 0
  overwatch 0 on
  overwatch 1 on
  assert_contains "$(cat "$HOME_DIR/stderr")" "Overwatch operation failed" \
    "a refused command reports failure without printing binding values"
  assert_not_contains "$(cat "$HOME_DIR/stderr")" at-bryde-ud \
    "a refused command must not leak the private binding's workspace"
  pass "invalid bounds and a second enable are refused without leaking the binding"
}

test_an_error_outcome_pauses_pickup() {
  overwatch 0 defer --outcome error
  assert_equals False "$(policy_field enabled)" "an error outcome disables pickup"
  overwatch 0 check
  assert_equals "" "$OVERWATCH_OUT" "a paused Overwatch prints no wake line"
  overwatch 0 off
  pass "an error outcome pauses pickup until it is re-enabled deliberately"
}

test_an_incomplete_binding_refuses_to_enable() {
  local field
  for field in project_id project_identifier workspace_slug; do
    write_binding
    python3 -c 'import json,sys
path = sys.argv[1]
binding = json.load(open(path))
binding.pop(sys.argv[2])
json.dump(binding, open(path, "w"))' "$BINDING" "$field"
    overwatch 1 on
    assert_absent "$HOME_DIR/state/overwatch.check.sh" \
      "enabling without $field must register no check"
  done
  printf '{"workspace_slug":"a","workspace_id":"b","project_id":"p","project_identifier":"PLAT"}\n' > "$BINDING"
  overwatch 1 on
  rm -f "$BINDING"
  overwatch 1 on
  assert_absent "$HOME_DIR/state/overwatch.check.sh" \
    "enabling without a binding at all must register no check"
  pass "an incomplete, ambiguous or missing tracker binding refuses to enable"
}

test_the_helper_reaches_no_tracker() {
  # The scope's only input is the local binding file, so a home whose binding
  # names a project that exists nowhere still enables: proving by contrast that
  # nothing here resolves a ticket, a state or a label against a live tracker.
  rm -rf "$HOME_DIR/state"
  printf '{"workspace_slug":"nowhere","project_id":"no-such-project","project_identifier":"ZZZ"}\n' > "$BINDING"
  overwatch 0 on
  assert_equals no-such-project "$(policy_field project_id)" \
    "the policy records the bound project without resolving it anywhere"
  overwatch 0 off
  pass "enabling resolves nothing against a tracker, only the local binding"
}

test_disabled_by_default_and_silent
test_enabling_records_scope_and_registers_the_check
test_the_check_repeats_until_an_outcome_is_recorded
test_empty_outcomes_back_off_and_the_budget_stops_pickup
test_the_pickup_budget_stops_new_intake
test_a_changed_binding_pauses_pickup
test_off_retires_the_check_and_preserves_work
test_bounds_and_double_enable_are_refused
test_an_error_outcome_pauses_pickup
test_an_incomplete_binding_refuses_to_enable
test_the_helper_reaches_no_tracker
