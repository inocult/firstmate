---
name: prep
description: Prepare this home and a repository for tracker missions. Use when the captain invokes /prep, or before the first mission against a repository this home has not run before. Confirms the session's tracker connector and the project it will act on, writes the home's minimal private tracker binding, creates any missing canonical triage label in that project once the captain confirms the exact list, and commissions the project's own domain-doc and tracker layout.
metadata:
  internal: true
---

# Prep

Prepping has two halves with different owners, and they are never mixed.
XO performs the home half directly because it is this home's private operational state.
A worker performs the project half through the project's selected delivery path, because XO never writes to a project.

[`docs/tracker-binding.md`](../../../docs/tracker-binding.md) fixes which tracker this home uses, the whole schema of the binding file this skill writes, and which surface performs each operation below; do not offer another tracker.
Every tracker read and write in this skill is XO acting through the session connector; there is no adapter, no credential in this home's configuration and no dependency to install.
This skill owns the canonical triage vocabulary and provisions it, so every prepared environment carries the same five roles instead of whatever a given project happens to have:

- `needs-triage` - filed but not yet classified; nobody has decided what kind of work it is or whether it is actionable.
- `needs-info` - classified but waiting on a missing answer, and blocked until someone supplies it.
- `ready-for-agent` - specified well enough for an agent to execute without further clarification.
- `ready-for-human` - actionable but reserved for a person, because it needs judgment, access or accountability an agent does not have.
- `wontfix` - deliberately not being done, kept on the record so it is not refiled.

These names and meanings are fixed here: never rename a role, never add a sixth, and never restate a role's meaning from whatever the project's own label description happens to say.
Every other label the project carries is none of this skill's business; leave it untouched.
The only genuine question this skill asks the captain about the repository is whether it is single-context or multi-context.

## Home half

XO performs these steps directly and reports the verified result.

1. Confirm the session has a tracker connector and which workspace it resolves to.
   List the workspaces the connector exposes and read back the one it will act in.
   Without a connector the home half cannot proceed at all: report that, name what is missing, and stop.
   How the connector is attached belongs to the harness, not to this repository.
2. Choose the project with the captain.
   List the workspace's projects through the connector and put the candidates to the captain rather than inferring one from a repository name.
   Record the chosen project's UUID.
3. Write the minimal binding at `XO_HOME/config/plane.json` from the confirmed workspace and project, exactly as the binding document's schema fixes it, and nothing else.
   No URL, no credentials, no state identifiers and no label identifiers: those are discovered live from the connector on every later use.
4. Provision the vocabulary.
   List the configured project's labels through the connector, compare all five canonical names against that listing, and settle that whole comparison before writing anything.
   Entering this step always compares against a listing read now, never against output from before someone changed the project's labels.
   The comparison is read-only.
   A label is a conflict when it normalizes onto a canonical name without being exactly it, comparing case-insensitively with every character that is not a letter or a digit ignored, which covers case, separators, surrounding whitespace and punctuation in one rule.
   So `Ready for agent`, `ready_for_agent` and `Ready-For-Agent` each conflict with `ready-for-agent`, and `Won't fix` conflicts with `wontfix`.
   Adoption stays exact - only the exact canonical name is ever the role.
   If the comparison finds any conflict, create nothing at all, not even the roles that compared clean, and report every conflict to the captain to settle in the tracker before prepping continues.
   Never adopt a variant, never rename one, and never create a label beside one: two spellings divide the queue between them and nothing ever reports it.
   Once the captain has settled them, re-enter this step by listing the labels again and comparing against what the project now carries.
   If the comparison is clean and the project already carries all five, nothing needs creating.
   Creating a role the project is missing is a write to the configured project, so put the exact list of labels to be created to the captain first, naming each one and saying they will appear in the configured project that their teammates share.
   This is a write to a live tracker, so silence is not confirmation, and neither is the captain's general agreement to run prep.
   Create only the labels they confirm, one at a time through the connector.
   If the captain declines or does not answer, create nothing: a prep that writes to the tracker only on an explicit yes, and otherwise creates nothing, is the intended outcome rather than a failure.
   If the connector cannot create a label, create nothing, and neither guess nor silently skip: halt the home half and report just the roles that are missing, with the meanings fixed above, for the captain to create in the tracker by hand.
   Re-entry lists the labels and compares again, so the roles the captain just created are then present and prepping continues.
5. Verify, then report exactly how far that verification reaches.
   Confirm all five canonical names appear exactly in a label listing read after the creates, whoever created the labels, because a create that failed, was rate-limited, or returned something read as "already exists" would otherwise reach the project's committed docs as a role the tracker does not carry.
   Confirm the project's states include the pickup and lifecycle names the binding document fixes, so a mission is not dispatched into a project whose workflow is missing one of them.
   Then read one page of the configured project's tickets through the connector, which proves the binding resolves to a real project the connector can read and writes nothing.
   Report the home half as verified only to that extent: the connector reaching the configured project, with the canonical roles and the named states really present.
   What that cannot catch is narrower: a state whose name matches but whose behaviour does not match the lifecycle position it carries, and any change made in the tracker after prep completes.
   A failure in any part of this step is a blocker rather than a warning, because missions cannot be claimed without a working connection.

If any of the five canonical roles is unresolved for any reason - a conflict the captain has not settled, a role missing from the label listing, no way to create it, a verification that did not pass - the home half does not complete and no ticket can be claimed.
The convention is the whole set, so an unsettled conflict on `wontfix` halts prepping exactly as one on `ready-for-agent` does; otherwise the worker commits a role name the tracker does not carry.
Report the home as unprepared, name what is outstanding, and do not commission the project half.

## Project half

Commissioning requires the implementation repository to already be a registered project: a local clone under `projects/`, with a standing delivery posture in the registry.
That is what a delivery path resolves through, and prep neither clones nor registers a repository.
`project-management` owns that intake; route the captain there when the repository is not registered.
When it is not, report that as the outstanding blocker and stop short of commissioning, leaving the verified home half exactly as it stands.

Commission this through the project's selected delivery path once the home half completes, and never before.
The brief carries the captain's answer to the single repository question.
Ask it every time; XO may recommend an answer and give its reason, but never decides it and never skips asking.

Nothing in the brief, and nothing in any document the worker writes, carries the home's tracker binding: not the workspace, not the project UUID, and not text read back out of the tracker.
That binding is private to this home and the project repository may be public.

The worker creates:

- The domain layout: `CONTEXT.md` plus `docs/adr/` for single-context, or a root `CONTEXT-MAP.md` pointing at per-context files for multi-context.
  `CONTEXT.md` records the project's domain vocabulary and the terms agents must use; `docs/adr/` records dated decisions, each as context, decision and consequences.
- `docs/agents/issue-tracker.md`, recording which tracker the issues live in as the binding document names it, that XO performs every read and write through its session's tracker connector, that selection requires the `ready-for-agent` label together with an eligible pickup state, and that GitHub holds pull requests only.
- `docs/agents/triage-labels.md`, recording the five canonical role names and this skill's meaning for each, as written above.
- A pointer to those files from the project's own `AGENTS.md`, created through `bin/xo-ensure-agents-md.sh`.

Repo-local engineering skills stay project-owned; this skill installs none and replaces none.
Never write XO's own `AGENTS.md` from this skill, because `xo-coding-guidelines` owns that file's placement and size discipline.

## Completion

Report only what has actually happened: what was verified and how far that reaches, which canonical roles this prep created, any conflict left with the captain, the confirmed project, and that the project half has been commissioned, naming the delivery path it went through.
Commissioning is dispatch, not delivery.
The project half's documents land under the project's own delivery path and merge authority, on that path's schedule rather than this skill's, so never report the layout as landed here.
The repository is prepped only once those documents are on its default branch.
That is a later condition to confirm separately, and no mission should assume it from this report.
Arming automatic pickup is a separate captain decision that `/overwatch on` owns.
