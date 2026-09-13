#!/usr/bin/env bash
# Live driver: bin/fm-watch.sh supervising a delivered ship task whose worker
# exited. Real tmux 3.7c on a private server, real bin/fm-pr-check.sh arming
# the merge poll, real bin/fm-wake-drain.sh acking the delivery signal, real
# bin/fm-crew-state.sh consulted by the watcher, real no-mistakes on PATH.
set -u
ROOT=${ROOT:?}; BASE=${BASE:?}; OUT=${OUT:?}
TOP=$(mktemp -d /tmp/fm-live-r2w.XXXX); export TMUX_TMPDIR=$TOP/tmuxtmp; mkdir -p "$TMUX_TMPDIR"; unset TMUX
PR=https://github.com/inocult/firstmate/pull/10
WENV="FM_POLL=1 FM_SIGNAL_GRACE=1 FM_STALE_ESCALATE_SECS=5 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999"
tmux new-session -d -s fmlive -n keepalive 'sleep 1200'
cp /usr/bin/sleep "$TOP/claude"   # a foreground process the tmux classifier reads as a live agent
cleanup() { tmux kill-server 2>/dev/null; rm -rf "$TOP"; }
trap cleanup EXIT
say() { printf '\n== %s\n' "$*"; }

# make_task <name> <status-line> <pane-cmd|""> [nocheck] -> prints home dir; window fmlive:fm-<name>
make_task() {
  local name=$1 line=$2 cmd=$3 nocheck=${4:-} h st id="held-$1" win
  h=$TOP/$name; st=$h/state; mkdir -p "$st"; win="fmlive:fm-$id"
  git init -q -b "fm/$id" "$h/wt" && git -C "$h/wt" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  if [ -n "$cmd" ]; then tmux new-window -d -t fmlive -n "fm-$id" "$cmd"; else tmux new-window -d -t fmlive -n "fm-$id"; fi
  printf 'window=%s\nworktree=%s\nkind=ship\nharness=claude\nbackend=tmux\n' "$win" "$h/wt" > "$st/$id.meta"
  printf '%s\n' "$line" > "$st/$id.status"
  FM_HOME=$h FM_STATE_OVERRIDE=$st "$ROOT/bin/fm-pr-check.sh" "$id" "$PR" 2>/dev/null | sed "s|^|    [$name] pr-check: |" >&2
  [ -z "$nocheck" ] || rm -f "$st/$id.check.sh"
  touch "$st/.last-check"
  printf '%s' "$h"
}
task_of() { printf 'held-%s' "$1"; }

# run_watch <label> <bindir> <home> <state> <max-secs> : runs the watcher, reports exit or still-supervising
run_watch() {
  local label=$1 bindir=$2 h=$3 st=$4 max=$5 pid i=0 rc
  rm -rf "$st/.watch.lock"
  env FM_HOME="$h" FM_STATE_OVERRIDE="$st" $WENV "$bindir/fm-watch.sh" > "$OUT/$label.stdout" 2> "$OUT/$label.stderr" &
  pid=$!
  while [ $i -lt $((max*10)) ]; do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; i=$((i+1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    echo "[$label] watcher still supervising after ${max}s: no wake surfaced"
  else
    wait "$pid"; rc=$?
    echo "[$label] watcher exited rc=$rc after $((i/10))s with: $(cat "$OUT/$label.stdout")"
  fi
}
drain_ack() {  # <bindir> <home> <state>
  local bindir=$1 h=$2 st=$3 line seq gen
  FM_HOME=$h FM_STATE_OVERRIDE=$st "$bindir/fm-wake-drain.sh" > "$OUT/drain.stdout" 2> "$OUT/drain.stderr"
  sed 's/^/    [drain] /' "$OUT/drain.stdout" | head -3
  line=$(grep WAKE_ACK_REQUIRED "$OUT/drain.stderr" | head -1)
  seq=$(printf '%s' "$line" | sed -n 's/.*--ack-through \([0-9]*\).*/\1/p'); gen=$(printf '%s' "$line" | sed -n 's/.*--recovery-generation \([^ ]*\).*/\1/p')
  [ -n "$seq" ] && FM_HOME=$h FM_STATE_OVERRIDE=$st "$bindir/fm-wake-drain.sh" --ack-through "$seq" --recovery-generation "$gen" >/dev/null 2>&1 && echo "    [drain] acked through $seq"
}
show_state() {  # <state> <task>
  local st=$1 task=$2 key
  echo "  triage log (distinct messages x count):"; cut -d' ' -f2- "$st/.watch-triage.log" 2>/dev/null | sort | uniq -c | sed 's/^/    /'; [ -s "$st/.watch-triage.log" ] || echo "    (none)"
  echo "  stale rows in .wake-queue: $(awk -F'\t' '$3=="stale"{n++} END{print n+0}' "$st/.wake-queue" 2>/dev/null)"
  echo "  markers:"; (cd "$st" && ls -a | grep -E '^\.(stale|wedge|hash|count)' | sed 's/^/    /')
}
first_then_second() {  # <label> <bindir> <home> <state> [pre-run2-hook]
  local label=$1 bindir=$2 h=$3 st=$4 hook=${5:-}
  run_watch "$label.run1" "$bindir" "$h" "$st" 8
  drain_ack "$bindir" "$h" "$st"
  [ -z "$hook" ] || eval "$hook"
  run_watch "$label.run2" "$bindir" "$h" "$st" 12
}

say "W1 FIXED: dead agent (bare bash) + pr= + armed merge poll, attended posture"
h=$(make_task w1 "done: PR $PR checks green" ""); st=$h/state; echo
tmux list-windows -t fmlive -F '    #{window_name} #{pane_current_command}' | grep held-w1
first_then_second w1-fixed "$ROOT/bin" "$h" "$st"; show_state "$st" "$(task_of w1)"

say "W1 BASE: same fixture at the base commit"
h=$(make_task w1b "done: PR $PR checks green" ""); st=$h/state; echo
first_then_second w1-base "$BASE/bin" "$h" "$st"; show_state "$st" "$(task_of w1b)"

say "W2 FIXED: away posture (.afk) - nothing queued for the daemon"
h=$(make_task w2 "done: PR $PR checks green" ""); st=$h/state; echo
first_then_second w2-afk "$ROOT/bin" "$h" "$st" ": > '$st/.afk'"; show_state "$st" "$(task_of w2)"

say "W3: non-terminal last line, wedge timer seeded 500s past threshold with 2 escalations"
h=$(make_task w3 'resolved [key=nm-01RUN-review]: firstmate accepted the finding' ""); st=$h/state; echo
run_watch w3.run1 "$ROOT/bin" "$h" "$st" 8
drain_ack "$ROOT/bin" "$h" "$st"
key=$(printf 'fmlive:fm-held-w3' | tr ':/.' '___')
pane_hash=$(. "$ROOT/bin/fm-backend.sh"; printf '%s' "$(fm_backend_capture tmux fmlive:fm-held-w3 40 fm-held-w3)" | md5sum | cut -d' ' -f1)
rm -rf "$TOP/w3b"; cp -a "$h" "$TOP/w3b"
for s in "$st" "$TOP/w3b/state"; do printf '%s' "$pane_hash" > "$s/.stale-$key"; echo $(( $(date +%s) - 500 )) > "$s/.stale-since-$key"; printf '2\n' > "$s/.wedge-escalations-$key"; done
echo "  seeded on both copies: .stale-$key=$pane_hash (already classified), .stale-since-$key 500s old, .wedge-escalations-$key=2"
run_watch w3-fixed.run2 "$ROOT/bin" "$h" "$st" 12; show_state "$st" "$(task_of w3)"
echo "  -- BASE on the same seeded state (FM_STALE_ESCALATE_SECS=5):"
run_watch w3-base.run2 "$BASE/bin" "$TOP/w3b" "$TOP/w3b/state" 12; show_state "$TOP/w3b/state" "$(task_of w3)"

say "W4 guard FIXED: same records but the agent is alive (foreground command named claude)"
h=$(make_task w4 "done: PR $PR checks green" "$TOP/claude 1200"); st=$h/state; echo
tmux list-windows -t fmlive -F '    #{window_name} #{pane_current_command}' | grep held-w4
first_then_second w4-live "$ROOT/bin" "$h" "$st"; show_state "$st" "$(task_of w4)"

say "W5 guard FIXED: dead agent, pr= recorded, merge poll retired (no check.sh)"
h=$(make_task w5 "done: PR $PR checks green" "" nocheck); st=$h/state; echo
ls "$st"/*.check.sh 2>/dev/null || echo "    (no check.sh)"
first_then_second w5-retired "$ROOT/bin" "$h" "$st"; show_state "$st" "$(task_of w5)"

say "W6 FIXED: task window closed after delivery (session alive)"
h=$(make_task w6 "done: PR $PR checks green" ""); st=$h/state; echo
first_then_second w6-gone "$ROOT/bin" "$h" "$st" "tmux kill-window -t fmlive:fm-held-w6"; show_state "$st" "$(task_of w6)"
echo "  reader on the same task: $(FM_HOME=$h FM_STATE_OVERRIDE=$st "$ROOT/bin/fm-crew-state.sh" held-w6)"
