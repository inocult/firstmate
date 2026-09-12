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
The five canonical triage roles are always the vocabulary; map them onto Plane's real states and labels rather than creating new ones.
The only genuine question this skill asks the captain about the repository is whether it is single-context or multi-context.

`docs/plane-missions.md` owns the configuration schema and its limits, and `bin/fm-plane.py --help` owns command syntax.
Read them rather than restating their contents here.

## Home half

Control performs these steps directly and reports the verified result.

1. Confirm Python 3.10+ and create the adapter's virtual environment from `bin/requirements-plane.txt`.
   Record that environment's interpreter as `FM_PLANE_PYTHON`; the same interpreter must serve every later adapter command.
2. Collect the connection facts from the captain: Plane URL, workspace slug, project UUID, implementation repository URL, coordination remote, and this instance's executor name.
   Prefer the remote streamable HTTP transport whenever the captain already has a reachable authenticated endpoint, because it needs no local server process.
   Credentials are named in the configuration and sourced from the captain's existing secrets system, never stored in it.
3. Run `doctor` before writing any identifier.
   It reports the project's actual states and labels and proposes the `ready-for-agent` label and the eligible pickup states.
4. Confirm the proposed identifiers with the captain, then write `FM_HOME/config/plane.json`.
   Never configure In Progress, In Review, Done, or cancelled states as pickup states.
5. Re-run `doctor` against the written configuration.
   A failure here is a blocker rather than a warning, because missions cannot be claimed without a working connection.

## Project half

Commission this through the project's selected delivery path once the home half verifies, and never before.
The brief carries the captain's answer to the single repository question.
Default to single-context, which fits almost every repository, and offer multi-context only when the repository shows genuine monorepo signals.

The worker creates:

- The domain layout, which is `CONTEXT.md` plus `docs/adr/` for single-context, or a root `CONTEXT-MAP.md` pointing at per-context files for multi-context.
- `docs/agents/issue-tracker.md`, recording that issues live in Plane, that the adapter owns every read and write, that selection requires the `ready-for-agent` label together with an eligible pickup state, and that GitHub holds pull requests only.
- `docs/agents/triage-labels.md`, mapping the five canonical roles onto the identifiers `doctor` confirmed.
- A pointer to those files from the project's own `AGENTS.md`, created through `bin/fm-ensure-agents-md.sh`.

Repo-local engineering skills stay project-owned; this skill installs none and replaces none.
Never write firstmate's own `AGENTS.md` from this skill, because `firstmate-coding-guidelines` owns that file's placement and size discipline.

## Completion

Report the verified connection, the confirmed label and pickup states, and the layout the worker landed.
Arming automatic pickup is a separate captain decision that `/overwatch on` owns.
