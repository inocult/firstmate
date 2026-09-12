# Definition of done for a no-mistakes brief: base 563ee04 vs target f693a0f

## BASE (before fix)
# Definition of done
Delivery contract: mode=no-mistakes
The task is complete only when committed on your branch.
When you believe it is complete, append `done: {summary}` to the status file and stop.
Firstmate will then instruct you to run /no-mistakes to validate and ship a PR.

## TARGET (after fix)
# Definition of done
Delivery contract: mode=no-mistakes
This task ships **no-mistakes**: you validate and ship the PR through the no-mistakes pipeline yourself.
Done is bound to this task's delivery mode: the only `done:` line that counts is `done: PR {url} checks green`, and its evidence is a PR whose checks are green, named by its full https:// URL.
A local commit with passing local checks, a started pipeline run, or an open PR still waiting on CI is not done; a `done:` line without that evidence is not a done, and firstmate treats it as a worker that stopped short of delivery, not as finished work.
Commit the implementation on your branch, append the nonterminal `working: implementation committed, starting no-mistakes` line, and start /no-mistakes in that same turn to validate and ship the PR.
Do not stop at the commit and do not wait for firstmate to tell you to start the pipeline: the commit is a milestone, never a gate, and there is no done line for it.
If an instruction to run /no-mistakes reaches you while your run is already active, reattach to that run; never start a second one.

## TARGET status protocol rule 4 (report site)
4. Report status by appending one line:
   `echo "{state}: {one short line}" >> '/tmp/fm-brief-live.jyMomt/state/live-no-mistakes.status'`
   States: working, needs-decision, blocked, paused, done, failed.
   Each append wakes firstmate, so report sparingly: only phase changes a supervisor
   would act on (setup done, bug reproduced, fix implemented, validation passed) and the
   needs-decision/blocked/paused/done/failed states. No step-by-step FYI progress lines;
   firstmate reads your pane for that.
   Whenever you mention a PR anywhere - a status line, your terminal, a summary - write its full
   https:// URL exactly as the forge printed it, never a bare number such as "PR 108"; firstmate
   copies that URL from your line rather than assembling one.
   A mid-task `working:` line (including setup complete) is nonterminal: do not end the
   turn after it; continue the same stage until a defined `done:` gate under Definition of done.
   Done is bound to this task's delivery mode: the only `done:` line that counts is `done: PR {url} checks green`, and its evidence is a PR whose checks are green, named by its full https:// URL.
   A local commit with passing local checks, a started pipeline run, or an open PR still waiting on CI is not done; a `done:` line without that evidence is not a done, and firstmate treats it as a worker that stopped short of delivery, not as finished work.
   Use `paused: {why}` - distinct from `blocked:` - ONLY when you are deliberately idling on a
   known external wait you expect to clear on its own (an upstream release, a rate-limit reset,
   a scheduled window): firstmate then leaves your idle pane alone and rechecks it on a long
   cadence instead of treating it as a possible wedge. Use `blocked:` when you are stuck and need help.
