---
name: prep
description: Prepare this home and a repository for tracker missions. Use when the captain invokes /prep, or before the first mission against a repository this home has not run before. Installs the adapter's dependencies, discovers the live label and state identifiers, creates any missing canonical triage label in the configured project once the captain confirms that specific list, writes the private tracker configuration, and commissions the project's own domain-doc and tracker layout.
metadata:
  internal: true
---

# Prep

Prepping has two halves with different owners, and they are never mixed.
Control performs the home half directly because it is this home's private operational state.
A worker performs the project half through the project's selected delivery path, because Control never writes to a project.

[`docs/tracker-binding.md`](../../../docs/tracker-binding.md) fixes which tracker this home uses and which surface performs each operation below; do not offer another tracker.
This skill owns the canonical triage vocabulary and provisions it, so every prepared environment carries the same five roles instead of whatever a given project happens to have:

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
   `docs/plane-missions.md` owns where that interpreter belongs: `FM_PLANE_PYTHON` is read from the environment firstmate is launched with, so exporting it only in this session's shell loses it at the next launch and every later adapter command fails on the missing SDK.
2. Collect the connection facts from the captain: the tracker URL, workspace slug, project UUID, implementation repository URL, coordination remote, the tracker transport the configuration schema names, and this instance's executor name.
   Credentials are named in the configuration and sourced from the captain's existing secrets system, never stored in it.
3. Write the connection half of `FM_HOME/config/plane.json` from those facts, then run `doctor`.
   `doctor` reads that file and fails without it, but the commands that load the setup-stage configuration, which skips the identifier checks so they run before the label, pickup and lifecycle identifiers exist, are named in the binding document.
4. Provision the vocabulary, then complete the configuration.
   Compare all five canonical names against every label the latest `doctor` run returned, and settle that whole comparison before writing anything.
   Entering this step always compares against a current `doctor`, never against output from before someone changed the project's labels.
   The comparison is read-only and needs no write surface.
   A label is a conflict when it normalizes onto a canonical name without being exactly it, comparing case-insensitively with every character that is not a letter or a digit ignored, which covers case, separators, surrounding whitespace and punctuation in one rule.
   So `Ready for agent`, `ready_for_agent` and `Ready-For-Agent` each conflict with `ready-for-agent`, and `Won't fix` conflicts with `wontfix`.
   Adoption stays exact - only the exact canonical name is ever the role.
   If the comparison finds any conflict, create nothing at all, not even the roles that compared clean, and report every conflict to the captain to settle in the tracker before prepping continues.
   Never adopt a variant, never rename one, and never create a label beside one: two spellings divide the queue between them and nothing ever reports it.
   Once the captain has settled them, re-enter this step by re-running `doctor` and comparing again, so the comparison reads the labels as they now stand.
   If the comparison is clean and the project already carries all five, nothing needs creating: go straight to the configuration below, with no write surface involved at all.
   Creating a role the project is missing is a write to the configured project, and the binding document names the surface that performs it and the conditions under which that surface refuses.
   Confirming that surface is a precondition, not a caution, and a confirmed surface authorizes nothing on its own.
   Put the exact list of labels to be created to the captain first, naming each one and saying they will appear in the configured project that their teammates share.
   This is a write to a live tracker, so silence is not confirmation, and neither is the captain's general agreement to run prep.
   Create only the labels they confirm, one at a time through that surface, then re-run `doctor` to pick up the new identifiers.
   If the captain declines or does not answer, create nothing and take the same course as having no write surface at all; a prep that writes to the tracker only on an explicit yes, and otherwise creates nothing, is the intended outcome rather than a failure.
   Without a write surface that performs the create - the binding document names none for this home, the named one refuses, or it cannot be confirmed - create nothing, and neither guess nor silently skip: halt the home half and report just the roles that are missing, with the meanings fixed above, for the captain to create in the tracker by hand.
   Re-entry re-runs `doctor` and compares again, which needs no write surface; the roles the captain just created are then present and prepping continues, so a home on any harness can reach a prepped state this way.
   Then confirm the identifiers with the captain and complete `FM_HOME/config/plane.json` with the eligible pickup states, the implementing, review and done lifecycle states, and the readiness label identifier taken from the `ready-for-agent` role.
   That readiness label identifier is the only label identifier the home stores; the other four roles are provisioned by name and need no stored ID.
5. Verify, then report exactly how far that verification reaches.
   First confirm all five canonical names appear exactly in the `labels` array of the most recent `doctor` run, whoever created the labels.
   The completion gate covers the whole set while only the readiness label identifier is stored, so verifying stored identifiers alone would leave four roles unchecked: a create that failed, was rate-limited, or returned something read as "already exists" would reach the project's committed docs as a role the tracker does not carry.
   Then check every identifier written in step 4 against those same `states` and `labels` arrays by the rule [`docs/plane-missions.md`](../../../docs/plane-missions.md) fixes for every configured identifier.
   What that cannot catch is narrower: a state whose name the captain confirmed but whose behaviour does not match the lifecycle position it was configured for, and any change made in the tracker after prep completes.
   Then run `list`, not `doctor`: the binding document records that `doctor` runs on the setup-stage configuration that skips the identifier checks step 4 satisfied, while `list` loads the completed configuration under full validation and reads one page of tickets without writing.
   Both of those reach the tracker only.
   Neither touches `coordination_remote`, which no adapter command opens until the first `claim` builds its registry, so check it read-only with `GIT_TERMINAL_PROMPT=0 timeout 45 git ls-remote <coordination_remote> 'refs/heads/fm-plane/*'`, the same way the registry bounds its own Git calls.
   Without both guards an HTTPS remote with no credential helper prompts for a username and hangs the session instead of failing.
   No matching refs is the normal answer on a remote no mission has used yet.
   Report the home half as verified only to that extent: the tracker reachable with the configured identifiers real, and the coordination remote reachable and readable.
   The push `claim` performs and the credentials the transport resolves at mission time remain unproven until the first mission.
   A failure in any part of this step is a blocker rather than a warning, because missions cannot be claimed without a working connection.
   A coordination remote that fails `ls-remote` is exactly that: `claim` pushes to it, so a home reported ready on a remote it cannot reach only moves the failure to the first mission.

If any of the five canonical roles is unresolved for any reason - a conflict the captain has not settled, a role missing from `doctor`'s labels, no write surface to create it through, an identifier that did not verify - the home half does not complete and no ticket can be claimed.
The convention is the whole set, so an unsettled conflict on `wontfix` halts prepping exactly as one on `ready-for-agent` does; otherwise the worker commits a role name the tracker does not carry.
Report the home as unprepared, name what is outstanding, and do not commission the project half.

## Project half

Commissioning requires the implementation repository to already be a registered project: a local clone under `projects/`, with a standing delivery posture in the registry.
That is what a delivery path resolves through, and prep neither clones nor registers a repository.
`project-management` owns that intake; route the captain there when the repository is not registered.
When it is not, report that as the outstanding blocker and stop short of commissioning, leaving the verified home half exactly as it stands.

Commission this through the project's selected delivery path once the home half completes, and never before.
The brief carries the captain's answer to the single repository question.
Ask it every time; Control may recommend an answer and give its reason, but never decides it and never skips asking.

Nothing in the brief, and nothing in any document the worker writes, carries the home's tracker configuration: not the tracker URL, workspace slug or project UUID, not a label or state identifier, and not text read back out of the tracker.
That configuration is private to this home and the project repository may be public.

The worker creates:

- The domain layout: `CONTEXT.md` plus `docs/adr/` for single-context, or a root `CONTEXT-MAP.md` pointing at per-context files for multi-context.
  `CONTEXT.md` records the project's domain vocabulary and the terms agents must use; `docs/adr/` records dated decisions, each as context, decision and consequences.
- `docs/agents/issue-tracker.md`, recording which tracker the issues live in as the binding document names it, that Control's surfaces own every read and write, that selection requires the `ready-for-agent` label together with an eligible pickup state, and that GitHub holds pull requests only.
- `docs/agents/triage-labels.md`, recording the five canonical role names and this skill's meaning for each, as written above.
- A pointer to those files from the project's own `AGENTS.md`, created through `bin/fm-ensure-agents-md.sh`.

Repo-local engineering skills stay project-owned; this skill installs none and replaces none.
Never write firstmate's own `AGENTS.md` from this skill, because `firstmate-coding-guidelines` owns that file's placement and size discipline.

## Completion

Report only what has actually happened: what was verified and how far that reaches, which canonical roles this prep created, any conflict left with the captain, the confirmed pickup states, and that the project half has been commissioned, naming the delivery path it went through.
Commissioning is dispatch, not delivery.
The project half's documents land under the project's own delivery path and merge authority, on that path's schedule rather than this skill's, so never report the layout as landed here.
The repository is prepped only once those documents are on its default branch.
That is a later condition to confirm separately, and no mission should assume it from this report.
Arming automatic pickup is a separate captain decision that `/overwatch on` owns.
