# Plane missions in XO

Plane is the shared backlog; each person's XO instance executes selected tickets through the existing XO lifecycle.
XO replaces the orchestration role of Pocock's `implement` workflow for Plane tickets while retaining repo-local engineering disciplines.
The bundled `breach` skill adapts Pocock's small `implement` entrypoint with attribution; repo-local engineering disciplines remain project-owned.

No script in this repository talks to Plane.
Every ticket read and write is performed by XO through the Plane connector the harness attaches to the session, as [tracker binding](tracker-binding.md) records; the scripts here hold only local policy and local state.

## Operating model

| Surface | Responsibility |
| --- | --- |
| Plane | Requirements, readiness, dependencies and final ticket status |
| XO | Ticket selection, filing the work it discovers or commissions as `needs-triage` tickets, worker dispatch, supervision and delivery reconciliation |
| Project skills | Design, TDD, debugging and review practices |
| GitHub PR | Implementation, checks, review and merge evidence |

The Plane assignee is independent of execution ownership and is never modified.
The worker's existing GitHub credentials determine PR authorship: your XO normally opens your PRs, while a colleague reviews under their own identity.
Agent self-review does not count as independent approval.
An authorized human or configured merge process merges under the existing project policy.
XO then verifies acceptance and the merged PR before moving the ticket to Done.

For the full planning, implementation and separate-review flow, read [XO delivery workflow](xo-delivery-workflow.md).

## XO skills

Use `/prep` to prepare this home and a repository for missions before the first one is dispatched.
Use `/operation` for an effort too big for one mission: it charts the effort as a map of decision tickets on the shared tracker and resolves them one at a time, until the cleared route becomes the ready-for-agent implementation tickets that `/overwatch` and `/breach` deliver.
Use `/breach <ticket>` for one directed implementation or `/overwatch on` for bounded automatic queue pickup.
Use `/overwatch off` to stop new intake while preserving active work, and `/overwatch status` to inspect its scope and bounds.
Codex uses the same skill names with `$` instead of `/`.
The [Overwatch skill](../skills/in-progress/overwatch/SKILL.md) owns the pickup policy, recovery and watcher integration.
The [Breach skill](../skills/in-progress/breach/SKILL.md) owns the attributed adaptation of Pocock's implementation entrypoint.
`bin/xo-overwatch.py --help` owns timer and policy command syntax.
That helper holds local policy only and never reads Plane; the timer wakes XO, and selection, reasoning and dispatch require a live supported XO agent session with the connector attached.
No new daemon is installed and no idle heartbeat behavior is changed.

## Setup

The [prep skill](../skills/in-progress/prep/SKILL.md) owns the setup procedure: `/prep` walks it end to end, preparing this home and commissioning the repository's own documentation through a worker on the project's delivery path.

Setup has to produce two things.
The session needs a Plane connector the harness attaches, resolving to the workspace whose tickets this home executes; this repository neither provisions nor configures it, and how it is attached belongs to the harness.
The home needs the minimal private binding at `XO_HOME/config/plane.json`, whose whole schema [tracker binding](tracker-binding.md) owns: the workspace and the configured project, and nothing else.
No actual At Bryde ticket, label or state IDs are bundled.

The states and labels that binding does not carry are discovered live from the connector at the moment of use, by the exact names the binding document fixes.
The readiness label is the planning team's promise that the ticket has sufficient scope and acceptance criteria.
Pickup requires both that label and an eligible Backlog or Todo state, plus the dependency checks the binding document records.
In Progress, In Review, Done and cancelled states are never pickup states.
Blocked is not one either, because it is the state XO files queued commissioned work in.

All colleagues must use the same canonical workspace and project for the same queue.
Each instance needs its own explicit `XO_HOME`.
For multiple projects, use separate private bindings and homes; do not mix bindings from different projects in one home.

## Lifecycle

[Tracker binding](tracker-binding.md) owns which surface performs each operation below and the boundary of each one, so this list carries only the order of the flow.

1. XO reads the configured project, selects an eligible ticket from the authorized scope, and reads its requirements.
2. XO claims the ticket by moving it to the implementing state, after checking the whole pickup predicate the binding document's claim boundary fixes against the connector's live reads.
   A ticket that is not in a pickup state is not claimable, so a second XO reading the same project sees the claimed ticket as ineligible.
3. XO creates the ordinary brief and local ledger row for the work, recording the ticket's display identifier on that row as a `Ticket: <identifier>` line, then dispatches through normal `xo-spawn.sh` with the chosen delivery mode and approval posture.
4. The worker uses repo-local engineering skills and validates affected monorepo consumers.
5. XO records the canonical PR URL on the ticket without changing ticket contents or assignment.
   Direct-PR work can register a draft early; no-mistakes work lets its pipeline own PR creation.
6. XO moves the ticket to the review state when the PR is ready, and back to implementing when corrections are needed.
7. XO verifies through GitHub that the linked PR merged and that the acceptance criteria hold, then moves the ticket to Done.
   XO never merges the PR to complete a ticket.

XO performs this synchronization on the existing supervision events; no new always-running polling service is installed.
An external move to canceled, closed or another unrelated state stops routine synchronization for reconciliation.
A ticket in the implementing state stays there while it waits for review, even when its worker exits.

## Limits

What the claim boundary checks is fixed by [tracker binding](tracker-binding.md); this section records what no check reaches.
Temporal prerequisites are conservatively required to be complete.
Custom relations and cross-project dependencies require explicit review and a supported mapping before automatic pickup.
A dependency mentioned only in prose cannot be inferred; the planning workflow must encode it or XO must stop and clarify.
A manual PR that was never linked to the ticket cannot be discovered by reading the ticket; teammates should attach their PR before starting implementation.
The claimed state alone does not detect overlapping changes across different tickets; XO must compare shared interfaces and validate downstream packages.

Plane and Git are separate systems, so the ticket and the PR are reconciled rather than updated together.
A failed ticket move leaves the local work as it stands, and XO reconciles before dispatch.
Two XO instances reading the same project at the same moment can both see one ticket as eligible; the state move is what resolves that, and an instance that finds the ticket already implementing skips it rather than dispatching a second worker.

## Recovery

A claimed ticket never expires on its own.
After a crash, read the ticket and inspect the branch and PR before resuming.
To hand a ticket back, move it to its original Backlog or Todo state, leave the labels unchanged, and record where the preserved work lives in the team handoff; removing the readiness label prevents a later new claim.
Handing work to another person requires confirming that the previous worker stopped, and does not revoke that worker's independent Git credentials.
A handoff with an existing PR needs manual recovery into the existing worktree and branch, following the normal XO recovery procedure; never bind a fresh implementation brief that would create a second branch or PR.
If a brief scaffold fails after the claim, inspect local artifacts before retrying, and never delete unlanded work to make a retry succeed.

## Verification and provenance

Run `bin/xo-test-run.sh tests/xo-overwatch.test.sh` for the local pickup policy, its bounds, cadence and watcher registration.
That suite needs no connector and no credentials, because nothing in this repository reaches the tracker.
Live Plane access through the session connector, the project's actual states and labels, and end-to-end worker launch remain setup-time validation requirements.

The [Pocock skill collection](https://github.com/mattpocock/skills) remains project-owned.
No private At Bryde source, ticket content or credentials are copied into this public fork.
