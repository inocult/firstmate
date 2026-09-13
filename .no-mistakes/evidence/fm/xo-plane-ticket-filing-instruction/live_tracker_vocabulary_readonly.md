# Live read-only check of the real tracker (Plane, workspace "At Bryde Ud", project PLAT "Platform")

Read through the session connector's `project list`, `state list` and `label list` actions on 2026-09-12. No write was performed.

## States in project PLAT (id 0212707d-4cab-4d11-af83-e3d3a3008fc1)

| name | group | description |
| --- | --- | --- |
| Backlog | backlog | (default state) |
| Todo | unstarted | |
| In Progress | started | |
| In Review | started | |
| Blocked | started | Waiting on an external dependency, decision, or resource. Must have a comment explaining the blocker. |
| Done | completed | |

The Blocked state the new rule files queued commissioned work in exists, and its own description matches the wording the binding document records ("waiting on an external dependency, decision or resource").
It sits in the `started` group, so the adapter's `doctor` would not even suggest it as a pickup candidate here; the never-configure line in docs/plane-missions.md is a defensive guard for projects that place it in `unstarted`.
Note: the state's description also asks for a comment explaining the blocker; the filing rule does not mention adding one.

## Labels in project PLAT

| name | description |
| --- | --- |
| needs-triage | Not yet assessed. The default state for anything newly filed. |
| needs-info | Blocked on a question only the reporter or a human can answer. |
| ready-for-agent | Well-specified enough that an agent can pick it up and execute without further clarification. |
| ready-for-human | Specified, but needs human judgement, credentials, or physical access to complete. |
| wontfix | Understood and deliberately not being done. |
| wayfinder:* (5 labels) | Wayfinder ticket types. |

`needs-triage` exists and its description is exactly the "default for anything newly filed" role the user intent and the new filing rule assign to it; `ready-for-agent` exists as the planning team's readiness label.
