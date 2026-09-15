# Tracker binding

This document is the single owner of which tracker holds this home's tickets, how that tracker is reached, which project the tickets belong to, which surface performs each ticket operation, and which operations no surface in this repository performs.
Skills speak only in the neutral vocabulary defined here and point here instead of asserting what a surface can do, so each capability is stated once and never assumed separately in a skill.
[`plane-missions.md`](plane-missions.md) owns the operating model, the filing rules and the lifecycle, and this document owns only the binding.

## This home's tracker

For this home, tickets live in Plane.
They are reached through the session connector, and through nothing else: no script in this repository talks to the tracker.
They belong to one configured project, named by the home's private binding at `XO_HOME/config/plane.json`.
Every ticket operation in this repository acts on that project alone, and a blocking edge into another project is refused rather than followed.

That binding file carries the workspace and the project and nothing else:

```json
{
  "workspace_slug": "YOUR_WORKSPACE",
  "project_id": "YOUR_PROJECT_UUID"
}
```

The file holds no URL, because the connector already knows where its workspace lives; no credentials, because the harness owns the connector's authentication; and no state or label identifiers, because those are discovered live from the connector on each use, by exact name.
The names discovered that way are the readiness label `ready-for-agent`, the triage label `needs-triage`, and the project's `Backlog`, `Todo`, `In Progress`, `In Review`, `Blocked` and `Done` states.
A name that resolves to no state or label, or to more than one, stops the operation rather than being guessed at.

## The surface

One surface exists, plus the captain acting by hand in the tracker.
A skill names the operation, and this document names the surface.

The session connector is a Plane MCP server the harness itself attaches to the session.
This repository does not provision, configure, or verify it, so nothing in this repository assumes it exists, and its tools are whatever the session discovers.
Before any write through it, confirm it resolves to the same workspace and the same project as the binding above; a connector that resolves elsewhere is not a surface for this home's tickets.
When the session has no connector, every operation below is reported for the captain to perform by hand; a skill never routes around the missing surface.

`bin/xo-overwatch.py` reads the binding file to record the scope its policy was enabled for and to notice that the binding changed underneath it.
It is not a tracker surface: it performs no ticket read or write, and the pickup it schedules is performed by XO through the connector.

## Vocabulary

| Neutral term | Plane concept |
| --- | --- |
| ticket | a work item in the configured project, addressed by its UUID, or by its display identifier where a connector tool accepts one |
| the tracker | the Plane workspace the session connector resolves to, which must be the workspace the binding names |
| the configured project | the one project every operation acts on, named by `project_id` |
| readiness label | the project label named exactly `ready-for-agent`, the planning team's promise that the ticket is specified well enough for an agent |
| triage label | the project label named exactly `needs-triage`, carried by work filed but not yet classified |
| pickup states | the project states a ticket may be claimed from: `Backlog` and `Todo` |
| lifecycle states (implementing, review, done) | the project states `In Progress`, `In Review` and `Done`, which a ticket moves through during delivery |
| the Blocked state | the project state named `Blocked`, whose own definition is waiting on an external dependency, decision or resource, where XO files commissioned work it must queue behind a dependency or time gate; it is never a pickup state |
| claim | XO's move of the ticket to `In Progress` through the connector, which is what marks the ticket as being worked |
| parent and child | the parent work-item link that makes one ticket a slice of another |
| blocking edges | the native work-item relations `blocked_by`, `start_after` and `finish_after` |

The five canonical triage labels, of which the readiness label and the triage label are two, are owned by the `prep` skill; this document names only the two that a ticket operation reads.

## Operations and their surfaces

Every operation below runs through the session connector, after the confirmation the last section requires, or is reported for the captain to perform by hand when no connector is available.

| Operation | Boundary |
| --- | --- |
| Resolve a display identifier such as `PLAT-27` to a ticket | the connector's work-item retrieve; confirm the returned ticket's project is the configured one before acting on it |
| Discover the project's states and labels | the connector's state and label listings, read by exact name at the moment of use and never cached into the binding |
| Create a project label | the connector's label create; used only by `prep`, which creates a missing canonical triage role and never applies a label to a ticket |
| List and filter tickets | the connector's work-item listing, filtered by label, state, parent and relation as far as its query surface allows; whatever the query cannot express is checked by reading the tickets it returns |
| Read one ticket | the connector's work-item retrieve, including its labels, state, parent and relations |
| Create a ticket | the connector's work-item create, with `needs-triage` at creation and never the readiness label |
| Verify eligibility and claim | read the ticket, confirm the readiness label, a pickup state, a title and description, no archived or draft flag, no linked PR, and every blocking edge inside the configured project finished; then move it to `In Progress` |
| Move a ticket between states | the connector's work-item update with a state field: to `In Progress` at dispatch or when correction work resumes, to `In Review` when the PR is ready, to `Blocked` when commissioned work must queue, and to `Done` at landing |
| Record the PR on the ticket | the connector's work-item link create, adding the canonical PR URL and changing nothing else on the ticket |
| Set or read a parent link | the connector's work-item update for the parent field, and its child listing for the reverse direction |
| Read and create blocking edges | the connector's work-item relation listing and create, within the configured project only |
| Comment on a ticket | the connector's work-item comment create, used when a state's own convention requires the reason in writing |
| Complete | confirm through GitHub that the linked PR merged and the acceptance criteria hold, then move the ticket to `Done` |

## Operations no surface in this repository performs

A skill must never assume one of these, and must never infer one from a connector tool's name.

- Follow a blocking edge into another project, interpret a custom relation, or infer a dependency stated only in prose.
- Move a ticket in a project other than the configured one.
- Merge a PR, or discover a PR that was never linked to the ticket.
- Prove that a session connector exists or that it resolves to the configured project; that is confirmed at the moment of use, never assumed.
- Apply the readiness label to any ticket, which is the planning team's promise and never XO's.

When a skill's procedure needs one of these, the skill does not route around this list.
It reports the missing operation for the captain to perform by hand when its procedure allows that, and otherwise stops and reports the specific missing operation.
