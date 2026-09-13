# Round 2 live validation: delivered ship task reads held for merge, not stale

Target 0b97351 (reader probe switched to strict `tmux list-panes -t`), compared
against BASE da0acc8. Real product, isolated: private tmux 3.7c server
(`TMUX_TMPDIR`), throwaway git worktree per task, isolated `FM_STATE_OVERRIDE`,
real `bin/fm-pr-check.sh` recording `pr=`/`pr_head=` and arming the merge poll
(`<id>.check.sh`), real `bin/fm-watch.sh`, `bin/fm-crew-state.sh`,
`bin/fm-wake-drain.sh` (with the real `--ack-through` ack), real `no-mistakes`
on PATH (throwaway repo => no attributed run, so the reader reaches its
no-run fallback). The worker's exit is modelled as the task window's shell
left bare (`bash` foreground, tmux classifier: agent dead) or the window /
session / server closed. Drivers: `round2-reader-driver.sh`,
`round2-watch-driver.sh`, `round2-watch-wedge-base-driver.sh`.

## Reader: crew-state-round2.transcript.txt

| Case | FIXED | BASE |
|---|---|---|
| S1 window closed, session + server alive (round-1 failure) | `done · status-log · PR held for merge (worker exited, merge poll armed): <PR>` | `unknown · pane · harness state unavailable` |
| S1 guards: poll retired / no pr= / kind=scout | `unknown · none · backend target gone` | n/a |
| S2 task session gone, server serving another session | held for merge | `unknown · pane · harness state unavailable` |
| S3 tmux server down | held for merge | `unknown · none · backend target gone` |
| S4 guard: tmux absent from PATH | `unknown · none · backend unreachable (tmux endpoint state: unreadable)` | n/a |
| S5 window present, bare shell, claude Stop-hook idle record | `done · status-log · PR ... checks green` (live path unchanged) | n/a |

The transcript also shows the raw tmux probes: `display-message -p -t <closed
window>` answers `%0 rc=0` (why BASE never saw the window gone) while
`list-panes -t` fails with `can't find window`.

## Watcher: watch-round2.transcript.txt, watch-round2-wedge-base.transcript.txt

Each case: run1 surfaces the delivery `signal:` once (expected), the queue is
drained and acked, run2 is the re-armed watcher.

| Case | Result |
|---|---|
| W1 FIXED dead agent + pr= + armed poll, attended | run2 keeps supervising; triage `absorbed stale (held for merge: <PR>, merge poll armed, agent gone)`; 0 stale rows; no `.stale-since-*` / `.wedge-escalations-*` |
| W1 BASE same fixture | run2 exits `stale: fmlive:fm-held-w1b` (the false alarm), 1 stale row queued |
| W2 FIXED away posture (`.afk`) | absorbed, 0 rows queued for the daemon |
| W3 FIXED non-terminal last line, `.stale-since` 500s old + 2 escalations seeded | absorbed; timer and count dropped; no wake |
| W3 BASE same seeding (fresh base fixture, FM_STALE_ESCALATE_SECS=5) | run2 exits `stale: ... (idle 5s, possible wedge, escalation 1)` |
| W4 guard: agent alive (`claude` foreground) with both records | still `stale:` |
| W5 guard: dead agent, pr= but poll retired | still `stale:` |
| W6 window closed after delivery | watcher skips the unreadable pane, no wake; reader on the same task reads held for merge |

Per-run stdout/stderr and drain output: `watch-round2/`.

## Baseline: baseline-suites-round2.log

`bin/fm-test-run.sh tests/fm-crew-state.test.sh tests/fm-watch-triage.test.sh`
(the two suites this change extends).

Not driven live: the herdr backend (husk pane) path; it needs a running herdr
desktop server, which is outside this run's isolation boundary.
