---
name: rig
description: Prepare this home and a repository for Plane missions. Use when the captain invokes /rig, or before the first mission against a repository this home has not run before. Installs the adapter's dependencies, discovers the live label and state identifiers, writes the private Plane configuration, and commissions the project's own domain-doc and tracker layout.
metadata:
  internal: true
---

# Rig

Rigging has two halves with different owners, and they are never mixed.
Control performs the home half directly because it is this home's private operational state.
A worker performs the project half through the project's selected delivery path, because Control never writes to a project.

Plane is always the tracker; do not offer another.
This skill owns the canonical triage vocabulary and provisions it, so every rigged environment carries the same five roles instead of whatever a given project happens to have:

- `needs-triage` - filed but not yet classified; nobody has decided what kind of work it is or whether it is actionable.
- `needs-info` - classified but waiting on a missing answer, and blocked until someone supplies it.
- `ready-for-agent` - specified well enough for an agent to execute without further clarification.
- `ready-for-human` - actionable but reserved for a person, because it needs judgment, access or accountability an agent does not have.
- `wontfix` - deliberately not being done, kept on the record so it is not refiled.

These names and meanings are fixed here: never rename a role, never add a sixth, and never restate a role's meaning from whatever the project's own label description happens to say.
Every other label the project carries is none of this skill's business; leave it untouched.
The only genuine question this skill asks the captain about the repository is whether it is single-context or multi-context.

`docs/plane-missions.md` owns the configuration schema and its limits, and `bin/fm-plane.py --help` owns command syntax.
Read them rather than restating their contents here.

## Home half

Control performs these steps directly and reports the verified result.

1. Confirm Python 3.10+ and create the adapter's virtual environment from `bin/requirements-plane.txt`.
   Record that environment's interpreter as `FM_PLANE_PYTHON`.
2. Collect the connection facts from the captain: Plane URL, workspace slug, project UUID, implementation repository URL, coordination remote, MCP transport, and this instance's executor name.
   Credentials are named in the configuration and sourced from the captain's existing secrets system, never stored in it.
3. Write the connection half of `FM_HOME/config/plane.json` from those facts, then run `doctor`.
   `doctor` reads that file and fails without it, but it is the one command loaded in setup mode, so it tolerates the label, pickup and lifecycle identifiers still being absent.
4. Compare the five canonical roles against the labels `doctor` returned and create every one the project is missing, using the wording above, so the project ends up carrying all five.
   The adapter lists labels but never writes them, so create them through the same Plane MCP server it connects to, then re-run `doctor` to pick up the new identifiers.
   Then confirm the identifiers with the captain and complete `FM_HOME/config/plane.json` with the eligible pickup states, the implementing, review and done lifecycle states, and `ready_label_id` taken from the `ready-for-agent` role.
   `ready_label_id` is the only label identifier the home stores, because it is the only one the adapter reads; the other four roles are provisioned by name and need no stored ID.
5. Verify, then report exactly how far that verification reaches.
   First check every identifier written in step 4 against the `states` and `labels` arrays `doctor` returned; no command validates that an ID names a real Plane object, so a well-formed but wrong label ID passes every check here and only surfaces later as tickets that never look ready.
   Then run `list`, not `doctor`: setup mode is exactly what skips the identifier checks step 4 satisfied, and `list` loads the completed configuration under full validation and reads one page of work items without writing.
   Both of those reach Plane only. Neither touches `coordination_remote`, which no adapter command opens until the first `claim` builds its registry, so check it read-only with `git ls-remote <coordination_remote> 'refs/heads/fm-plane/*'`; no matching refs is the normal answer on a remote no mission has used yet.
   Report the home half as verified only to that extent: Plane reachable with the configured identifiers real, and the coordination remote reachable and readable. The push `claim` performs and the credentials the transport resolves at mission time remain unproven until the first mission.
   A failure in any part is a blocker rather than a warning, because missions cannot be claimed without a working connection.

## Project half

Commission this through the project's selected delivery path once the home half verifies, and never before.
The brief carries the captain's answer to the single repository question.
Ask it every time; Control may recommend an answer and give its reason, but never decides it and never skips asking.

The worker creates:

- The domain layout, which is `CONTEXT.md` plus `docs/adr/` for single-context, or a root `CONTEXT-MAP.md` pointing at per-context files for multi-context.
- `docs/agents/issue-tracker.md`, recording that issues live in Plane, that the adapter owns every read and write, that selection requires the `ready-for-agent` label together with an eligible pickup state, and that GitHub holds pull requests only.
- `docs/agents/triage-labels.md`, recording the five canonical role names and this skill's meaning for each.
  The brief carries those names and meanings as written above, never an identifier and never text read back out of Plane, because the Plane configuration is private to this home and the project repository may be public.
- A pointer to those files from the project's own `AGENTS.md`, created through `bin/fm-ensure-agents-md.sh`.

Repo-local engineering skills stay project-owned; this skill installs none and replaces none.
Never write firstmate's own `AGENTS.md` from this skill, because `firstmate-coding-guidelines` owns that file's placement and size discipline.

## Completion

Report what was verified and how far that reaches, which canonical roles this rig had to create, the confirmed pickup states, and the layout the worker landed.
Arming automatic pickup is a separate captain decision that `/overwatch on` owns.
