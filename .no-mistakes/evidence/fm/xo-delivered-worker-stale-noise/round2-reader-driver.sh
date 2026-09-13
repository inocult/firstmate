#!/usr/bin/env bash
# Live driver: bin/fm-crew-state.sh on a delivered ship task whose worker exited.
# Real tmux 3.7c on a private server (TMUX_TMPDIR), real bin/fm-pr-check.sh
# arming the merge poll, real no-mistakes on PATH (throwaway repo => no run).
set -u
ROOT=${ROOT:?}; BASE=${BASE:?}
H=$(mktemp -d /tmp/fm-live-r2.XXXX); STATE=$H/state; mkdir -p "$STATE" "$H/tmuxtmp"
export TMUX_TMPDIR=$H/tmuxtmp; unset TMUX
PR=https://github.com/inocult/firstmate/pull/10
ID=feat-held; WIN=fmlive:fm-$ID
say() { printf '\n== %s\n' "$*"; }
reader() { # <label> <bindir>
  printf '[%s] ' "$1"; FM_HOME=$H FM_STATE_OVERRIDE=$STATE "$2/fm-crew-state.sh" $ID; }
cleanup() { tmux kill-server 2>/dev/null; rm -rf "$H"; }
trap cleanup EXIT

say "fixture: throwaway worktree on fm/$ID, task window with the worker exited (bare bash)"
git init -q -b fm/$ID "$H/wt" && git -C "$H/wt" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
tmux new-session -d -s fmlive -n keepalive 'sleep 900'
tmux new-window -t fmlive -n fm-$ID   # default shell: the worker's agent already exited
sleep 0.5
printf 'window=%s\nworktree=%s\nkind=ship\nharness=claude\nbackend=tmux\n' "$WIN" "$H/wt" > "$STATE/$ID.meta"
printf 'done: PR %s checks green\n' "$PR" > "$STATE/$ID.status"
say "bin/fm-pr-check.sh records pr= and arms the merge poll"
FM_HOME=$H FM_STATE_OVERRIDE=$STATE "$ROOT/bin/fm-pr-check.sh" $ID "$PR"; echo "rc=$?"
echo "meta:"; sed 's/^/    /' "$STATE/$ID.meta"; ls -l "$STATE/$ID.check.sh" | sed 's/^/    /'
echo "tmux windows:"; tmux list-windows -t fmlive -F '    #{window_name} #{pane_current_command}'
say "window still open, worker exited (pane shell remains), no idle record - FIXED"
reader FIXED "$ROOT/bin"

say "S1: task window closed, session and server alive (the 2026-09 incident shape)"
tmux kill-window -t "$WIN"; echo "tmux windows:"; tmux list-windows -t fmlive -F '    #{window_name}'
echo "probe: tmux display-message -p -t $WIN ->" "$(tmux display-message -p -t "$WIN" '#{pane_id}' 2>&1)" "rc=$?"
echo "probe: tmux list-panes -t $WIN ->" "$(tmux list-panes -t "$WIN" -F '#{pane_id}' 2>&1)" "rc=$?"
reader FIXED "$ROOT/bin"
reader BASE "$BASE/bin"

say "S1-guard: window closed, pr= recorded but merge poll retired (check.sh gone)"
mv "$STATE/$ID.check.sh" "$H/check.aside"; reader FIXED "$ROOT/bin"; mv "$H/check.aside" "$STATE/$ID.check.sh"
say "S1-guard: window closed, merge poll armed but no pr= recorded"
cp "$STATE/$ID.meta" "$H/meta.aside"; sed -i '/^pr=/d;/^pr_head=/d' "$STATE/$ID.meta"; reader FIXED "$ROOT/bin"; cp "$H/meta.aside" "$STATE/$ID.meta"
say "S1-guard: window closed, both records but kind=scout"
sed -i 's/^kind=ship$/kind=scout/' "$STATE/$ID.meta"; reader FIXED "$ROOT/bin"; cp "$H/meta.aside" "$STATE/$ID.meta"

say "S2: whole task session gone while the server still serves another session"
tmux new-session -d -s other -n idle 'sleep 900'; tmux kill-session -t fmlive
echo "tmux sessions:"; tmux list-sessions -F '    #{session_name}'
reader FIXED "$ROOT/bin"
reader BASE "$BASE/bin"

say "S3: tmux server down"
tmux kill-server; echo "probe:" "$(tmux list-windows -t fmlive 2>&1)"
reader FIXED "$ROOT/bin"
reader BASE "$BASE/bin"

say "S4-guard: tmux unreachable (absent from PATH) with both records"
mkdir -p "$H/nopath"; for f in /usr/bin/*; do b=${f##*/}; [ "$b" = tmux ] && continue; ln -s "$f" "$H/nopath/$b" 2>/dev/null; done
( export PATH=$H/nopath; reader FIXED "$ROOT/bin" )

say "S5: window present, shell remaining, claude Stop-hook idle record (live pane path unchanged)"
tmux new-session -d -s fmlive -n keepalive 'sleep 900'; tmux new-window -t fmlive -n fm-$ID; sleep 0.5
gen=$("$ROOT/bin/fm-busy-event.sh" arm "$STATE" $ID); "$ROOT/bin/fm-busy-event.sh" apply "$STATE" $ID idle --gen "$gen" --source claude-hook --event stop >/dev/null
reader FIXED "$ROOT/bin"
