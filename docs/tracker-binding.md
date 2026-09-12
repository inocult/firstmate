# Tracker binding

This document is the single owner of which tracker holds this home's tickets, how that tracker is reached, which project the tickets belong to, which surface performs each ticket operation, and which operations no surface in this repository performs.
Skills speak only in the neutral vocabulary defined here and point here instead of asserting what a surface can do, so each capability is stated once and never assumed separately in a skill.
[`plane-missions.md`](plane-missions.md) owns the configuration schema, its limits, the shared claim mechanics and recovery, `bin/fm-plane.py --help` owns command syntax, and this document owns only the binding.

## This home's tracker

For this home, tickets live in Plane.
They are reached through the Plane MCP.
They belong to one configured project: the project whose identifier the home's private tracker configuration at `FM_HOME/config/plane.json` records, in the workspace and at the URL that same file names.
Every ticket operation in this repository acts on that project alone, and a blocking edge into another project is refused rather than followed.

## Surfaces

Two surfaces exist.
A skill names the operation, and this document names the surface.

The adapter is `bin/fm-plane.py`, invoked with the interpreter `FM_PLANE_PYTHON` names.
It reaches the tracker through its own MCP client, which the tracker configuration points either at a stdio server the adapter starts for each command or at a remote streamable HTTP server.
That client lives inside the adapter's process: the session cannot call its tools, and no skill may describe the adapter's server as a surface the session reaches.
Every adapter command except `check` opens that connection before dispatching, so a command that changes nothing in the tracker still fails when the tracker is unreachable; only `check` runs without it.
`doctor` proves only that this client connects and which tools that server advertises; it proves nothing about any operation outside the table below, so a passing `doctor` never licenses an operation this document does not list.

The session connector is a Plane MCP server the harness itself attaches to the session, when one is configured.
This repository does not provision, configure, or verify it, so nothing in this repository assumes it exists, and its tools are whatever the session discovers.
Before any write through it, confirm it resolves to the same workspace and the same project as the tracker configuration; a connector that resolves elsewhere is not a surface for this home's tickets.
Apart from the captain acting by hand in the tracker, it is the only surface through which an operation from the last section can happen, and a skill's own procedure says whether either is allowed.

## Vocabulary

| Neutral term | Plane concept | Bound by |
| --- | --- | --- |
| ticket | a work item in the configured project, addressed by its UUID and never by its display identifier | the item argument of every adapter lifecycle command |
| the tracker | the Plane instance at the configured URL and workspace | `plane_url` and `workspace_slug` |
| the configured project | the one project every operation acts on | `project_id` |
| readiness label | the project label named exactly `ready-for-agent`, the planning team's promise that the ticket is specified well enough for an agent | `ready_label_id`, the only label identifier any surface reads |
| pickup states | the states a ticket may be claimed from, drawn from the tracker's backlog and unstarted groups | `pickup_state_ids` |
| claim | the shared record at `refs/heads/fm-plane/<hash>` on the coordination remote that gives one executor the ticket, together with the move to implementing | `coordination_remote` and `executor` |
| lifecycle states (implementing, review, done) | the three project states a claimed ticket moves through | `states.implementing`, `states.review` and `states.done` |
| parent and child | the parent work-item link that makes one ticket a slice of another | the `parent` field the tracker returns on a ticket, which the adapter passes through and never interprets |
| blocking edges | the native work-item relations `blocked_by`, `start_after` and `finish_after` | the relation listing `claim` reads |

The five canonical triage labels, of which the readiness label is one, are owned by the `prep` skill; this document binds only the one label identifier the home stores.

## Operations and their surfaces

| Operation | Surface | Boundary |
| --- | --- | --- |
| Discover the project's states and labels | adapter `doctor` | reads every state and label with a setup-stage configuration and suggests the readiness label id and the pickup candidates; writes nothing |
| Provision a project label | adapter `ensure-label` | creates the named label in the configured project, or adopts the one already carrying that exact name; refuses a name that exists twice or differs only by case, separators or punctuation; refuses when the connected server advertises no label-create tool; never applies a label to a ticket |
| List tickets | adapter `list` | returns one unfiltered page of the configured project's work items with pagination metadata; readiness and pickup-state selection happens by reading the page and is verified again at claim |
| Read one ticket | inside adapter `claim`, `sync`, `bind`, `complete` and `release`, and inside `pr`, `review` and `resume` through `sync` | retrieves the ticket by UUID as part of those commands; there is no standalone read |
| Verify eligibility and claim | adapter `claim` | requires the readiness label, a pickup state, a title and description, no archived or draft flag, no linked PR, and every blocking edge inside the configured project finished; then writes the claim record and moves the ticket to implementing |
| Inspect a claim | adapter `status` | reads the claim record and changes nothing in the tracker, but still requires the adapter's tracker connection to open |
| Repair the tracker projection | adapter `sync` | re-applies the claimed phase's lifecycle state and PR link after an interrupted update |
| Bind a local task | adapter `bind` | scaffolds the brief and writes the private execution receipt `data/<id>/plane.json` |
| Validate ownership at dispatch | adapter `check` | run by `bin/fm-spawn.sh` whenever that receipt exists; reads the claim record only and never the tracker |
| Record the PR on the ticket | adapter `pr` | adds one work-item link and changes no other ticket field |
| Move to review, return to implementing | adapter `review` and adapter `resume` | sets the lifecycle state while preserving the claim |
| Complete | adapter `complete` | confirms the linked PR merged through the GitHub API and then sets done; never merges |
| Release an unstarted claim | adapter `release` | restores the pickup state recorded at claim; refused once a PR is registered |
| Transfer to another executor | adapter `transfer` | rewrites the claim record and changes nothing in the tracker, but still requires the adapter's tracker connection to open |
| Automatic pickup policy and timer | `bin/fm-overwatch.py` | local policy and watcher registration only; reads and writes nothing in the tracker |
| Resolve a display identifier such as `PLAT-27` to a ticket UUID | session connector | its work-item tool declares a retrieve-by-identifier action for exactly this; use it only after confirming, as the Surfaces section requires, that the connector resolves to the same workspace and the same project as the tracker configuration, and hand the returned UUID to the adapter |

The adapter reaches the tracker with these MCP calls and no others: `state/list`, `label/list`, `label/create`, `workitem/list`, `workitem/retrieve`, `workitem/update` restricted to the state field, `workitem_link/list`, `workitem_link/create` and `workitem_relation/list`, falling back to the legacy tool names the server advertises when the resource tools are absent.

## Operations no surface in this repository performs

A skill must never assume one of these from the adapter, from a passing `doctor`, or from a server the adapter starts for itself.

- Create a ticket, or change its title, description, assignees, priority, labels or any other content.
- Apply a label to a ticket or remove one, including the readiness label; `ensure-label` writes the project vocabulary and touches no ticket.
- Filter a listing by label, state, parent or any other field; `list` returns one unfiltered page.
- List a parent's children, set or clear a parent, or compute the frontier, the open and unblocked children of a parent.
- Create, change or remove a blocking edge; `claim` reads them and refuses on an unfinished one.
- Follow a blocking edge into another project, interpret a custom relation, or infer a dependency stated only in prose.
- Comment on a ticket, or read its comments.
- Move a ticket to any state other than its recorded pickup state or the three lifecycle states.
- Discover a PR that was never linked to the ticket.
- Merge a PR.
- Prove that a session connector exists or that it resolves to the configured project.

When a skill's procedure needs one of these, the skill does not route around this list.
It performs the operation through a session connector confirmed as above when its procedure allows that, reports the missing operation for the captain to perform by hand when its procedure allows that, and otherwise stops and reports the specific missing operation.
