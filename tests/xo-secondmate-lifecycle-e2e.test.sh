#!/usr/bin/env bash
# tests/xo-secondmate-lifecycle-e2e.test.sh - the happy-path secondmate operator
# flow, end to end, against one shared world:
#
#   seed -> spawn -> routed send -> backlog handoff -> recovery respawn -> teardown
#
# Each phase asserts the durable contracts the consolidation audit lists, so the
# many former positive unit tests (registry scope/charter/clone/mode, spawn meta,
# bare-window send, recovery respawn, teardown of an empty home, backlog handoff)
# collapse into one lifecycle. The path-boundary safety invariants and the
# lease-specific paths live in xo-secondmate-safety.test.sh.
#
# Coverage anchored here (must not regress):
#   - registry line records scope (from a filled charter brief) and project list
#   - charter is copied into the subhome
#   - remote-backed projects are cloned with their origin URL preserved
#   - a no-mistakes project is initialized (init + doctor) in the NEW subhome clone
#     and the parent project clone is never mutated (no write through a project)
#   - spawn meta records kind=secondmate, home=, and the project list; launch runs
#     in the subhome with the persistent charter and cleared operational overrides
#   - a bare `xo-<id>` send targets the window recorded in THIS home's meta
#   - backlog items move verbatim into the subhome and leave the main backlog
#   - recovery respawns from the durable registry + persistent home
#   - teardown removes meta and the registry route only after removing the home
set -u

# shellcheck source=tests/secondmate-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/secondmate-helpers.sh"

TMP_ROOT=$(xo_test_tmproot xo-secondmate-lifecycle)
export XO_BACKEND=tmux

HOME_DIR="$TMP_ROOT/main home"
SUB="$TMP_ROOT/design-home"
SUB_ABS=
FAKEBIN=
LOG="$TMP_ROOT/tmux.log"
PANE="$TMP_ROOT/pane.txt"
ALPHA_ORIGIN=
BETA_ORIGIN=

# --- shared world + seed ----------------------------------------------------
setup_world() {
  mkdir -p "$HOME_DIR/projects" "$HOME_DIR/data" "$HOME_DIR/state"
  xo_git_init_commit "$HOME_DIR/projects/alpha"
  xo_git_init_commit "$HOME_DIR/projects/beta"
  xo_git_init_commit "$HOME_DIR/projects/gamma"
  xo_git_add_origin "$HOME_DIR/projects/alpha" "$TMP_ROOT/remotes/alpha.git"
  xo_git_add_origin "$HOME_DIR/projects/beta" "$TMP_ROOT/remotes/beta.git"
  xo_git_add_origin "$HOME_DIR/projects/gamma" "$TMP_ROOT/remotes/gamma.git"
  cat > "$HOME_DIR/data/projects.md" <<EOF
- alpha [direct-PR +yolo] - alpha project (added 2026-06-22)
- beta [direct-PR] - beta project (added 2026-06-22)
- gamma - gamma project (added 2026-06-22)
EOF
  ALPHA_ORIGIN=$(git -C "$HOME_DIR/projects/alpha" remote get-url origin)
  BETA_ORIGIN=$(git -C "$HOME_DIR/projects/beta" remote get-url origin)

  # One combined fakebin: tmux + treehouse (spawn/send/teardown) and no-mistakes
  # (gamma initialization during seed).
  FAKEBIN=$(make_fake_tmux "$TMP_ROOT/fake")
  make_fake_no_mistakes "$TMP_ROOT/fake" >/dev/null

  # A filled charter brief whose routing scope differs from the charter summary,
  # so the registry must read the scope from the brief, not invent a generic one.
  XO_SECONDMATE_SCOPE='customer onboarding from brief' \
    scaffold_secondmate_charter "$HOME_DIR" design 'customer onboarding charter' alpha beta gamma \
    || fail "filled secondmate charter scaffold failed"
}

phase_seed() {
  local out
  out=$(PATH="$FAKEBIN:$PATH" XO_HOME="$HOME_DIR" \
    "$ROOT/bin/xo-home-seed.sh" design "$SUB" alpha beta gamma) \
    || fail "seed failed"
  SUB_ABS=$(cd "$SUB" && pwd -P)

  assert_contains "$out" "home=$SUB_ABS" "seed did not report the subhome"
  assert_present "$SUB/.xo-secondmate-home" "seed did not mark the subhome"
  assert_present "$SUB/data/charter.md" "seed did not copy the charter into the subhome"
  assert_grep 'customer onboarding charter' "$SUB/data/charter.md" "charter body was not copied verbatim"

  # Projects cloned; remote-backed origins preserved.
  assert_present "$SUB/projects/alpha/.git" "alpha was not cloned"
  assert_present "$SUB/projects/beta/.git" "beta was not cloned"
  assert_present "$SUB/projects/gamma/.git" "gamma was not cloned"
  [ "$(git -C "$SUB/projects/alpha" remote get-url origin)" = "$ALPHA_ORIGIN" ] \
    || fail "alpha clone did not preserve its origin URL"
  [ "$(git -C "$SUB/projects/beta" remote get-url origin)" = "$BETA_ORIGIN" ] \
    || fail "direct-PR beta clone did not preserve its origin URL"

  # no-mistakes init runs in the NEW clone, never the parent project.
  assert_present "$SUB/projects/gamma/.no-mistakes-init" "no-mistakes project was not initialized in the subhome"
  assert_present "$SUB/projects/gamma/.no-mistakes-doctor" "no-mistakes project was not doctored in the subhome"
  assert_absent "$HOME_DIR/projects/gamma/.no-mistakes-init" "seed wrote no-mistakes state through the parent project"

  # Registry line: scope from the filled brief, project list, no legacy owns field.
  assert_grep '- design - customer onboarding charter' "$HOME_DIR/data/secondmates.md" "registry summary not from the charter"
  assert_grep 'scope: customer onboarding from brief' "$HOME_DIR/data/secondmates.md" "registry scope not from the filled brief"
  assert_grep 'projects: alpha, beta, gamma' "$HOME_DIR/data/secondmates.md" "registry did not record the project list"
  assert_no_grep 'owns:' "$HOME_DIR/data/secondmates.md" "registry used the legacy owns field"

  # Delivery modes preserved in the subhome registry; validation passes.
  [ "$(XO_HOME="$SUB" "$ROOT/bin/xo-project-mode.sh" alpha)" = "direct-PR on" ] \
    || fail "alpha delivery mode not preserved in the subhome"
  [ "$(XO_HOME="$SUB" "$ROOT/bin/xo-project-mode.sh" beta)" = "direct-PR off" ] \
    || fail "beta delivery mode not preserved in the subhome"
  XO_HOME="$HOME_DIR" "$ROOT/bin/xo-home-seed.sh" validate >/dev/null || fail "registry validation failed after seed"

  pass "seed: registry scope+projects, charter copied, clones+origins, no-mistakes init in subhome only"
}

phase_spawn() {
  : > "$LOG"
  PATH="$FAKEBIN:$PATH" XO_HOME="$HOME_DIR" XO_CONFIG_OVERRIDE="$HOME_DIR/parent-config" \
    XO_FAKE_TMUX_LOG="$LOG" XO_FAKE_TMUX_CAPTURE="$PANE" \
    "$ROOT/bin/xo-spawn.sh" design "$SUB" codex --secondmate >/dev/null \
    || fail "secondmate spawn failed"

  local meta="$HOME_DIR/state/design.meta"
  assert_grep 'kind=secondmate' "$meta" "spawn meta did not record kind=secondmate"
  assert_grep "home=$SUB_ABS" "$meta" "spawn meta did not record the subhome"
  assert_grep 'projects=alpha, beta, gamma' "$meta" "spawn meta did not record the project list"
  # Launch ran in the subhome, with the persistent charter and cleared overrides,
  # and never ran a project-style treehouse get.
  assert_grep "XO_HOME='$SUB_ABS'" "$LOG" "secondmate launch did not set XO_HOME to the subhome"
  assert_grep 'XO_ROOT_OVERRIDE= XO_STATE_OVERRIDE= XO_DATA_OVERRIDE= XO_PROJECTS_OVERRIDE=' "$LOG" "launch did not clear operational overrides"
  assert_grep 'XO_CONFIG_OVERRIDE=' "$LOG" "launch did not clear the config override"
  assert_grep "$SUB_ABS/data/charter.md" "$LOG" "launch did not use the persistent charter"
  assert_no_grep 'notify=' "$LOG" "secondmate codex launch included the parent turn-end notify hook"
  assert_no_grep 'turn-ended' "$LOG" "secondmate codex launch referenced a parent turn-ended signal"
  assert_no_grep 'treehouse get' "$LOG" "secondmate spawn ran a project treehouse get"
  pass "spawn: launches in the subhome with persistent charter, records routing meta"
}

phase_send() {
  : > "$LOG"
  printf '❯\n' > "$PANE"
  # The meta window (xo:xo-design) must win over a foreign same-named
  # window returned by list-windows. Include the recorded endpoint in the fake
  # inventory so the recovery-grade liveness check can verify it exists.
  PATH="$FAKEBIN:$PATH" XO_HOME="$HOME_DIR" XO_FAKE_TMUX_WINDOW="xo:xo-design
other-session:xo-design" \
    XO_FAKE_TMUX_LOG="$LOG" XO_FAKE_TMUX_CAPTURE="$PANE" \
    "$ROOT/bin/xo-send.sh" xo-design 'route this work' >/dev/null 2>&1 \
    || fail "xo-send failed for a bare xo window with home metadata"
  # design is a kind=secondmate target, so the durable inbox record carries the
  # from-xo marker and original payload. The terminal receives only the
  # constant doorbell, routed through this home's authoritative meta window.
  local record="$HOME_DIR/state/design.inbox/001.msg" body
  assert_present "$record" "send did not enqueue the secondmate request"
  body=$(bash -c '. "$1"; xo_task_inbox_body "$2"' _ "$ROOT/bin/xo-task-inbox-lib.sh" "$record")
  assert_contains "$body" '[xo-from-xo]' "the inbox request was not marked as from-xo"
  assert_contains "$body" 'route this work' "the original request text did not survive the marker"
  assert_grep 'send-keys -t xo:xo-design -l : XO instruction waiting:' "$LOG" "send did not ring the window recorded in this home's meta"
  assert_no_grep 'route this work' "$LOG" "send typed the payload instead of only the doorbell"
  assert_no_grep 'send-keys -t other-session:xo-design' "$LOG" "send targeted a foreign same-named window"
  pass "send: a bare xo-<id> secondmate enqueues a marked request and rings the meta window"
}

phase_handoff() {
  # The move is delegated to `tasks-axi mv`; skip cleanly when it is absent (the
  # downstream recovery and teardown phases do not depend on this phase).
  if ! command -v tasks-axi >/dev/null 2>&1; then
    echo "skip: tasks-axi not found (backlog handoff delegates to it)"
    return 0
  fi
  cat > "$HOME_DIR/data/backlog.md" <<'EOF'
## In flight
- [ ] live-task - active work (repo: alpha, since 2026-06-20)

## Queued
- [ ] feat-x - add feature x (repo: alpha)
- [ ] feat-y - add feature y (repo: beta) blocked-by: feat-x - waits
- [ ] bug-z - fix bug z (repo: gamma)

## Done
- [x] old-task - shipped thing - local main (merged 2026-06-19)
EOF
  local out before
  out=$(PATH="$FAKEBIN:$PATH" XO_HOME="$HOME_DIR" XO_FAKE_TMUX_LOG="$LOG" \
    XO_FAKE_TMUX_CAPTURE="$PANE" \
    "$ROOT/bin/xo-backlog-handoff.sh" design feat-x feat-y) \
    || fail "handoff failed for in-scope items"
  assert_contains "$out" "handed off 2 item(s) to design" "handoff did not report the moved items"

  assert_no_grep 'feat-x' "$HOME_DIR/data/backlog.md" "feat-x was not removed from the main backlog"
  assert_no_grep 'feat-y' "$HOME_DIR/data/backlog.md" "feat-y was not removed from the main backlog"
  assert_grep 'bug-z' "$HOME_DIR/data/backlog.md" "out-of-scope bug-z was wrongly removed"
  assert_grep 'live-task' "$HOME_DIR/data/backlog.md" "in-flight item was wrongly removed"

  assert_grep '- [ ] feat-x - add feature x (repo: alpha)' "$SUB/data/backlog.md" "feat-x did not arrive verbatim"
  assert_grep '- [ ] feat-y - add feature y (repo: beta) blocked-by: feat-x - waits' "$SUB/data/backlog.md" "feat-y line not preserved verbatim"
  awk '/^## Queued/{q=1;next} /^## /{q=0} q && /feat-x/{found=1} END{exit found?0:1}' "$SUB/data/backlog.md" \
    || fail "feat-x did not land under the Queued section"

  # Idempotent: a second handoff neither errors nor duplicates, and leaves main alone.
  before=$(cat "$HOME_DIR/data/backlog.md")
  PATH="$FAKEBIN:$PATH" XO_HOME="$HOME_DIR" XO_FAKE_TMUX_LOG="$LOG" \
    XO_FAKE_TMUX_CAPTURE="$PANE" \
    "$ROOT/bin/xo-backlog-handoff.sh" design feat-x feat-y >/dev/null 2>&1 \
    || fail "idempotent re-run failed"
  [ "$(grep -cF -- '- [ ] feat-x - add feature x (repo: alpha)' "$SUB/data/backlog.md")" -eq 1 ] \
    || fail "idempotent re-run duplicated feat-x in the subhome backlog"
  [ "$before" = "$(cat "$HOME_DIR/data/backlog.md")" ] || fail "idempotent re-run mutated the main backlog"
  pass "handoff: in-scope items move verbatim, out-of-scope stays, idempotent"
}

phase_recovery() {
  # Simulate a restart: drop the live meta, then respawn from the registry +
  # persistent home (no explicit home argument).
  rm -f "$HOME_DIR/state/design.meta"
  PATH="$FAKEBIN:$PATH" XO_HOME="$HOME_DIR" XO_FAKE_TMUX_LOG="$LOG" XO_FAKE_TMUX_CAPTURE="$PANE" \
    "$ROOT/bin/xo-spawn.sh" design "echo relaunch" --secondmate >/dev/null 2>&1 \
    || fail "recovery respawn failed"
  local meta="$HOME_DIR/state/design.meta"
  assert_grep "home=$SUB_ABS" "$meta" "respawn did not preserve the persistent home from the registry"
  assert_grep 'projects=alpha, beta, gamma' "$meta" "respawn did not preserve the project list from the registry"
  assert_grep 'window=xo:xo-design' "$meta" "respawn did not reconstruct the direct-report window"
  pass "recovery: respawns from the durable registry and persistent home"
}

phase_teardown() {
  local teardown_out corr rec
  corr=$(XO_HOME="$HOME_DIR" bash -c '
    . "$1"
    xo_pending_reply_create "$2" "$2/state" design "New routed work is in your backlog."
  ' _ "$ROOT/bin/xo-pending-reply-lib.sh" "$HOME_DIR") \
    || fail "could not seed receiver wake retirement state"
  rec="$HOME_DIR/state/pending-replies/$corr"
  XO_HOME="$HOME_DIR" bash -c '
    . "$1"
    xo_pending_reply_set "$2" phase resolved
    xo_pending_reply_set "$2" delivered_epoch 1
  ' _ "$ROOT/bin/xo-pending-reply-lib.sh" "$rec" \
    || fail "could not settle receiver wake retirement state"
  printf 'confirmed:%s\n' "$corr" > "$HOME_DIR/state/.backlog-handoff-design.wake-pending"
  : > "$LOG"
  teardown_out=$(PATH="$FAKEBIN:$PATH" XO_HOME="$HOME_DIR" XO_FAKE_TMUX_LOG="$LOG" XO_FAKE_TMUX_CAPTURE="$PANE" \
    "$ROOT/bin/xo-teardown.sh" design 2>&1) \
    || fail "teardown failed for the empty secondmate home"
  printf '%s\n' "$teardown_out" | grep -F 'Backlog:' >/dev/null \
    && fail "secondmate teardown emitted a main-backlog completion reminder"
  assert_absent "$SUB" "teardown did not remove the retired secondmate home"
  assert_absent "$HOME_DIR/state/design.meta" "teardown did not clear the parent meta"
  assert_absent "$HOME_DIR/state/.backlog-handoff-design.wake-pending" \
    "teardown left receiver wake state that could poison a replacement route"
  assert_absent "$rec" "teardown left the retired receiver wake correlation"
  assert_no_grep '- design ' "$HOME_DIR/data/secondmates.md" "teardown did not remove the registry route"
  # The parent's source projects are untouched (no write through a parent home).
  assert_present "$HOME_DIR/projects/alpha" "teardown disturbed a parent project"
  pass "teardown: removes the home, then clears meta and the registry route"
}

setup_world
phase_seed
phase_spawn
phase_send
phase_handoff
phase_recovery
phase_teardown
