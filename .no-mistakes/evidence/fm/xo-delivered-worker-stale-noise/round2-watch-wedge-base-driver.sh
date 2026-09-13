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

say "W3 BASE: fresh base-commit fixture, non-terminal last line, wedge timer seeded 500s past threshold with 2 escalations (FM_STALE_ESCALATE_SECS=5)"
h=$(make_task w3base 'resolved [key=nm-01RUN-review]: firstmate accepted the finding' ""); st=$h/state; echo
run_watch w3-base.run1 "$BASE/bin" "$h" "$st" 8
drain_ack "$BASE/bin" "$h" "$st"
key=$(printf 'fmlive:fm-held-w3base' | tr ':/.' '___')
pane_hash=$(. "$ROOT/bin/fm-backend.sh"; printf '%s' "$(fm_backend_capture tmux fmlive:fm-held-w3base 40 fm-held-w3base)" | md5sum | cut -d' ' -f1)
printf '%s' "$pane_hash" > "$st/.stale-$key"; echo $(( $(date +%s) - 500 )) > "$st/.stale-since-$key"; printf '2\n' > "$st/.wedge-escalations-$key"
echo "  seeded: .stale-$key=$pane_hash, .stale-since-$key 500s old, .wedge-escalations-$key=2"
run_watch w3-base.run2 "$BASE/bin" "$h" "$st" 12; show_state "$st" "$(task_of w3base)"
echo "  wedge escalation count after run2: $(cat "$st/.wedge-escalations-$key" 2>/dev/null || echo none)"
