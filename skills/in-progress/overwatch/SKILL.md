---
name: overwatch
description: Enable, pause or inspect automatic pickup of tickets carrying the readiness label in a configured XO home, and handle its registered watcher events.
metadata:
  internal: true
---

# Overwatch

XO watches the agreed queue and dispatches Breach when capacity is available.
This skill is a new XO orchestration layer; Breach is the adaptation of Pocock's implement workflow.
Load `plane-missions` for the claim and delivery contract and read `bin/xo-overwatch.py --help` for the local control commands.
[`docs/tracker-binding.md`](../../../docs/tracker-binding.md) owns which surface performs each ticket operation named here and which operations no surface performs; every one of them is XO acting through the session connector.
The helper holds local policy only - bounds, cadence, the recorded scope and the registered check - and reads no ticket itself.

## Enable, pause and status

`/overwatch on` enables automatic implementation only for the project in this home's tracker binding.
If no binding has been written, run the `prep` setup procedure and resolve the intended project before enabling.
Treat `/overwatch` without an action as status/help, not an instruction to start new work.
Before `on`, confirm through the connector that it resolves to the bound workspace and project, and that the readiness label and the pickup and lifecycle states named in the binding document exist there by those exact names.
Do not enable this in a persistent standing worker's home unless the main XO has routed that queue to it.

The helper defaults to two open executions, a five-minute check interval and ten successful pickups per activation; the user may choose other bounds.
Report the scope and bounds when enabling, then run the first pickup check immediately.
The check interval is a minimum: actual wakes follow the existing watcher's check cadence.
`/overwatch off` stops new pickup and retires the timer; it does not stop workers, discard claims or abandon PRs.
`/overwatch status` reports its policy and current claimed work without scanning unrelated projects.

## Wake and pickup

The helper registers `overwatch.check.sh` through XO's hash-validated custom-check mechanism.
Maintain exactly one existing supervision cycle while it is enabled, even with no workers; registration alone does not start a watcher.
After session start, inspect a persisted enabled policy, verify its check is registered and the ordinary watcher is live, and resume the same scope.
Never create a separate daemon or treat an idle terminal as spare capacity.

On `overwatch:` wakes, heartbeats or task completion, reconcile existing claimed tickets and worker/PR state first.
A registered due wake persists until an outcome is recorded; use the normal durable-wake acknowledgement protocol after handling it.
Check `status` and confirm the recorded scope and binding are unchanged before any new claim.
If the binding changed, the budget is exhausted, or tracker state is uncertain, run `off` and report the specific blocker once.

Count all this home's nonterminal claimed tickets toward the slot limit, including held work and PRs waiting for review.
Enumerate them from the local ledger and confirm each one's state against the connector; uncertain or missing local records require reconciliation before filling slots.
Do not take over a ticket already being implemented elsewhere, infer that a claim has lapsed, or change human assignees.

Read the configured project through the connector in paginated batches, retaining the cursor during the scan.
Consider only implementation tickets carrying the readiness label in a pickup state; read acceptance criteria and blocking edges before ranking eligible work by priority, then oldest creation time and ticket ID.
Pocock's to-spec also applies this label: exclude parent specs, epics, operation maps and decision tickets from automatic intake, and never execute a parent alongside its child slices.
Read parent and child relationships and the project's tracker conventions as far as the connector exposes them; if the ticket's role is unclear, hold it for classification instead of treating the label alone as implementation authority.
Compare package/interface scope against active work and sequence genuinely dependent changes.
If no safe candidate is found, record `defer --outcome empty`; the timer backs off to at most one hour and stays silent to the user.
If all slots are occupied, record `defer --outcome busy`; still reconcile PRs through normal supervision.

Invoke Breach for one selected ticket at a time, with this policy as the recorded authorization to implement that ticket.
Breach must move the ticket to the implementing state before dispatch; a ticket that has already left its pickup state means skip it, not an error permitting duplicate work.
Record `defer --outcome picked` for each successful new claim, including one whose dispatch subsequently needs recovery.
Count successful claims exactly once in the local ledger; after interruption reconcile the ledger and policy counter before selecting more work.
Fill only the remaining slots and remaining pickup budget, then return to supervision.
An absent connector, a transport failure, an ambiguous claim outcome or an unresolved authorization question pauses new pickup; preserve all existing work and run `off`.

Enabling Overwatch grants bounded implementation pickup, not new merge, deployment or credential authority.
Pocock planning skills and human decisions still establish what is ready; this skill never manufactures work to remain busy.
