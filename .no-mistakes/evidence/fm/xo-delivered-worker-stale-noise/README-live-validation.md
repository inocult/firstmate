# Live validation: delivered ship task reads held for merge, not stale

Fixture (real product, isolated): a private tmux server (`tmux -L`), a throwaway
git worktree on branch `fm/feat-held`, an isolated `FM_STATE_OVERRIDE` state dir,
`bin/fm-pr-check.sh feat-held https://github.com/inocult/firstmate/pull/10` to
record `pr=`/`pr_head=` and publish the real merge poll (`feat-held.check.sh`),
status log `done: PR ... checks green`, and a task window whose agent exited
leaving a bare `bash` (tmux classifier: agent dead). Real `bin/fm-watch.sh`,
`bin/fm-crew-state.sh`, `bin/fm-wake-drain.sh`, real `no-mistakes` on PATH.
"BASE" = the same scripts at the base commit da0acc8.

Each watcher transcript shows the realistic two-run flow: run1 surfaces the
delivery `signal:` once (expected), the queue is drained and acked, run2 is the
re-armed watcher.

| Transcript | Scenario | Result |
|---|---|---|
| watch-fixed.transcript.txt | dead agent + pr= + armed poll, attended | run2 keeps supervising; triage log `absorbed stale (held for merge: <PR>, merge poll armed, agent gone)`; no stale row in `.wake-queue`; no `.stale-since-*` / `.wedge-escalations-*` |
| watch-base.transcript.txt | same fixture, BASE | run2 exits with `stale: fmlive:fm-feat-held` (the false alarm) |
| watch-afk.transcript.txt | same, away posture (`.afk`) | absorbed, nothing queued for the daemon |
| watch-wedge-fixed.transcript.txt / watch-wedge5-fixed.transcript.txt | seeded `.stale-since` 500s old + 2 escalations, non-terminal last line | absorbed; timer and count dropped; no wake |
| watch-wedge-base.transcript.txt / watch-wedge5-base.transcript.txt | same seeded state, BASE (5s interval compresses the 240s cadence) | `stale: ... (idle 5s, possible wedge, escalation 1)` re-alarm |
| watch-live-agent.transcript.txt | same records, agent process alive (`claude` foreground) | still surfaces `stale:` (guard) |
| watch-poll-retired.transcript.txt | dead agent, pr= but no check.sh | still surfaces `stale:` (guard) |
| watch-window-gone.transcript.txt | window closed in a live session | pane capture fails, window skipped, no wake (both versions) |
| crew-state-server-down.transcript.txt | reader, tmux server down | FIXED: `done · status-log · PR held for merge (worker exited, merge poll armed): <PR>`; BASE: `unknown · none · backend target gone`; poll retired / scout: `unknown · none · backend target gone` |
| crew-state-live.transcript.txt | reader, session alive, window closed or session missing | `unknown · pane · harness state unavailable` before AND after: real tmux `display-message -p -t` silently falls back to a default pane (rc=0), so `pane_readable` never fails while any session exists and the gone path is not reached |
| crew-state-live.transcript.txt | reader, tmux absent from PATH (unreachable) | `unknown · none · backend unreachable (tmux endpoint state: unreadable)` |
| crew-state-idle-record.transcript.txt | reader, shell-remaining pane with a real claude Stop-hook idle record | `done · status-log · PR ... checks green` (live/idle path unchanged) |
| baseline-suites.log | `bin/fm-test-run.sh tests/fm-crew-state.test.sh tests/fm-watch-triage.test.sh` | both suites pass |

Not driven live: the herdr backend (husk pane) path. It needs the captain's real
herdr daemon, which is outside this run's isolation boundary.
