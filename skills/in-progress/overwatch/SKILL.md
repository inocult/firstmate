---
name: overwatch
description: Enable, pause or inspect automatic pickup of tickets carrying the readiness label in a configured Firstmate home, and handle its registered watcher events.
metadata:
  internal: true
---

# Overwatch

Control watches the agreed queue and dispatches Breach when capacity is available.
This skill is a new Firstmate orchestration layer; Breach is the adaptation of Pocock's implement workflow.
Load `plane-missions` for the shared-claim and delivery contract and read `bin/fm-overwatch.py --help` for the local control commands.
[`docs/tracker-binding.md`](../../../docs/tracker-binding.md) owns which surface performs each ticket operation named here and which operations no surface performs.

## Enable, pause and status

`/overwatch on` enables automatic implementation only for the project, repository and executor in this home's confirmed tracker configuration.
If no scope has been configured, discover it through the `prep` setup procedure and resolve the intended project before enabling.
Treat `/overwatch` without an action as status/help, not an instruction to start new work.
Before `on`, confirm that the readiness label, pickup states and lifecycle states resolve against the tracker through the surface the binding document names for that read.
Do not enable this in a persistent cell lead's home unless main Control has routed that queue to it.

The helper defaults to two open executions, a five-minute check interval and ten successful pickups per activation; the user may choose other bounds.
Report the scope and bounds when enabling, then run the first pickup check immediately.
The check interval is a minimum: actual wakes follow the existing watcher's check cadence.
`/overwatch off` stops new pickup and retires the timer; it does not stop operatives, discard claims or abandon PRs.
`/overwatch status` reports its policy and current claimed work without scanning unrelated projects.

## Wake and pickup

The helper registers `overwatch.check.sh` through Firstmate's hash-validated custom-check mechanism.
Maintain exactly one existing supervision cycle while it is enabled, even with no operatives; registration alone does not start a watcher.
After session start, inspect a persisted enabled policy, verify its check is registered and the ordinary watcher is live, and resume the same scope.
Never create a separate daemon or treat an idle terminal as spare capacity.

On `overwatch:` wakes, heartbeats or task completion, reconcile existing claimed executions and worker/PR state first.
A registered due wake persists until an outcome is recorded; use the normal durable-wake acknowledgement protocol after handling it.
Check `status` and confirm the configuration hash/scope is unchanged before any new claim.
If configuration changed, the budget is exhausted, or tracker or registry state is uncertain, run `off` and report the specific blocker once.

Count all this home's nonterminal claimed executions toward the slot limit, including reservations, held work and PRs waiting for review.
Use the shared registry as authority and the local execution ledger to enumerate them; uncertain or missing local records require reconciliation before filling slots.
Do not steal another executor's work, infer an expired claim, or change human assignees.

Read the configured project in paginated batches, retaining the cursor during the scan.
Consider only implementation tickets carrying the readiness label in configured pickup states; read acceptance criteria and blocking edges before ranking eligible work by priority, then oldest creation time and ticket ID.
Pocock's to-spec also applies this label: exclude parent specs, epics, operation maps and decision tickets from automatic intake, and never execute a parent alongside its child slices.
Read parent and child relationships and the project's tracker conventions as far as the surfaces in the binding document expose them; if the ticket's role is unclear, hold it for classification instead of treating the label alone as implementation authority.
Compare package/interface scope against active work and sequence genuinely dependent changes.
If no safe candidate is found, record `defer --outcome empty`; the timer backs off to at most one hour and stays silent to the user.
If all slots are occupied, record `defer --outcome busy`; still reconcile PRs through normal supervision.

Invoke Breach for one selected ticket at a time, with this policy as the recorded authorization to implement that ticket.
Breach must win the claim before dispatch; a competing claim means skip that ticket, not an error permitting duplicate work.
Record `defer --outcome picked` for each successful new claim, including one whose dispatch subsequently needs recovery.
Count successful claims exactly once in the local ledger; after interruption reconcile the ledger and policy counter before selecting more work.
Fill only the remaining slots and remaining pickup budget, then return to supervision.
A transport failure, ambiguous claim outcome or unresolved authorization question pauses new pickup; preserve all existing work and run `off`.

Enabling Overwatch grants bounded implementation pickup, not new merge, deployment or credential authority.
Pocock planning skills and human decisions still establish what is ready; this skill never manufactures work to remain busy.
