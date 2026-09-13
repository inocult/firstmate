# Plane missions in the Control edition

Plane is the shared backlog; each person's Control instance executes selected tickets through the existing Firstmate lifecycle.
This adapter replaces the orchestration role of Pocock's `implement` workflow for Plane tickets while retaining repo-local engineering disciplines.
The bundled `breach` skill adapts Pocock's small `implement` entrypoint with attribution; repo-local engineering disciplines remain project-owned.

## Operating model

| Surface | Responsibility |
| --- | --- |
| Plane | Requirements, readiness, dependencies and final ticket status |
| Control | Ticket selection, worker dispatch, supervision and delivery reconciliation |
| Project skills | Design, TDD, debugging and review practices |
| GitHub PR | Implementation, checks, review and merge evidence |
| Shared Git claim | One active implementation across participating Control instances |

The Plane assignee is independent of execution ownership and is never modified.
The operative's existing GitHub credentials determine PR authorship: your Firstmate normally opens your PRs, while a colleague reviews under their own identity.
Agent self-review does not count as independent approval.
An authorized human or configured merge process merges under the existing project policy.
Control then verifies acceptance and the merged PR before moving the ticket to Done.

For the full planning, implementation and separate-review flow, read [Control delivery workflow](control-delivery-workflow.md).

## Control skills

Use `/prep` to prepare this home and a repository for missions before the first one is dispatched.
Use `/operation` for an effort too big for one mission: it charts the effort as a map of decision tickets on the shared tracker and resolves them one at a time, until the cleared route becomes the ready-for-agent implementation tickets that `/overwatch` and `/breach` deliver.
Use `/breach <ticket>` for one directed implementation or `/overwatch on` for bounded automatic queue pickup.
Use `/overwatch off` to stop new intake while preserving active work, and `/overwatch status` to inspect its scope and bounds.
Codex uses the same skill names with `$` instead of `/`.
The [Overwatch skill](../skills/in-progress/overwatch/SKILL.md) owns the pickup policy, recovery and watcher integration.
The [Breach skill](../skills/in-progress/breach/SKILL.md) owns the attributed adaptation of Pocock's implementation entrypoint.
`bin/fm-overwatch.py --help` owns timer and policy command syntax.
The timer only wakes Control; selection, reasoning and dispatch require a live supported Firstmate agent session.
No new daemon is installed and no idle heartbeat behavior is changed.

## Setup

The [prep skill](../skills/in-progress/prep/SKILL.md) owns the setup procedure: `/prep` walks it end to end, preparing this home and commissioning the repository's own documentation through a worker on the project's delivery path.
This section owns what that setup has to produce, and is what the skill and a by-hand operator both work from: the prerequisites, the configuration schema, and the rule each value has to satisfy, so an operator configuring `plane.json` by hand satisfies what is below rather than following a second procedure.

Requires Git, Python 3.10+, the optional MCP SDK in `bin/requirements-plane.txt`, and a reachable authenticated Plane MCP server.
The SDK belongs in its own virtual environment, and `FM_PLANE_PYTHON` must name that environment's Python executable in the environment Firstmate is launched with.
Adapter commands must be invoked with that same interpreter.
Each instance needs its own explicit `FM_HOME` and executor name.

Store the following configuration privately at `FM_HOME/config/plane.json`.
Replace example values with actual repository, workspace, project and state identifiers.
No actual At Bryde ticket, label or state IDs are bundled.

```json
{
  "plane_url": "https://plane.example.com",
  "workspace_slug": "YOUR_WORKSPACE",
  "project_id": "YOUR_PROJECT_UUID",
  "repository_url": "https://github.com/YOUR_ORG/YOUR_MONOREPO",
  "coordination_remote": "git@github.com:YOUR_ORG/YOUR_MONOREPO.git",
  "executor": "mathieu-control",
  "ready_label_id": "READY_FOR_AGENT_LABEL_UUID",
  "pickup_state_ids": ["BACKLOG_STATE_UUID", "TODO_STATE_UUID"],
  "states": {
    "implementing": "IN_PROGRESS_STATE_UUID",
    "review": "IN_REVIEW_STATE_UUID",
    "done": "DONE_STATE_UUID"
  },
  "mcp": {
    "command": "uvx",
    "args": ["plane-mcp-server==0.3.2", "stdio"],
    "env_from": {
      "PLANE_API_KEY": "PLANE_API_KEY",
      "PLANE_WORKSPACE_SLUG": "PLANE_WORKSPACE_SLUG",
      "PLANE_BASE_URL": "PLANE_BASE_URL"
    }
  }
}
```

The example Plane server version is a compatibility target, not an automatic upgrade of your existing server.
Use your installed server command when appropriate and run `doctor` to verify its advertised tools.
Set credential environment variables through your existing secrets system; never put token values in the tracked repository.
The MCP workspace/base environment values must match this configuration.
For a remote streamable HTTP server, replace `mcp` with `url` and optional `headers_from`, a map from header names to environment-variable names containing complete header values.
Interactive OAuth setup remains with your MCP client; this adapter does not implement an OAuth login flow.

`doctor` is where `ready_label_id`, `pickup_state_ids` and the lifecycle state ids come from: it loads this configuration in setup mode, so it runs while those identifiers are still absent, and it returns the ticket tracker project's actual states and labels together with a suggested `ready-for-agent` label ID and the pickup candidates in its backlog and unstarted groups.
It suggests that label ID only when exactly one label carries the name exactly, so a missing or ambiguous one has to be configured explicitly.
Every identifier written here must be the id of the state or label whose name it is being configured for, because `doctor` returns each name beside its id and an id copied off a neighbouring entry is still a real id.
The label is the planning team's promise that the ticket has sufficient scope and acceptance criteria.
Pickup requires both this label and an eligible Backlog/Todo state, plus the existing dependency and shared-claim checks.
In Progress, In Review, Done and cancelled states must never be configured as pickup states.
The adapter preserves labels and assignees throughout delivery; the shared claim and lifecycle state prevent duplicate pickup even while the label remains.
Old configurations using `states.ready` must migrate to these two fields; the label is not a workflow state.

All colleagues must use the same canonical `plane_url`, workspace, project and `coordination_remote` for the same queue.
Prefer a private coordination repository if even opaque work-item IDs and executor names are sensitive.
The claim records contain no ticket descriptions, API keys or implementation content.
This public Firstmate fork is not an appropriate default for private team execution records.

## Lifecycle

`bin/fm-plane.py --help` and its subcommand help own the command syntax.
[Tracker binding](tracker-binding.md) owns which surface performs each operation below and the boundary of each command, so this list carries only the order of the flow.

1. `list` returns a page of Plane tickets including pagination metadata.
   Control selects an eligible ticket from the authorized scope and reads its requirements.
2. `claim` uses the ticket UUID and a unique request ID, verifies readiness and dependencies, reserves it remotely, then updates Plane to In progress.
   Retries use the same request ID.
3. `bind` creates the ordinary Firstmate brief and a private execution receipt for a local task.
   Control still files the local execution-ledger entry and uses normal `fm-spawn.sh` dispatch with the chosen delivery mode and approval posture.
4. The operative uses repo-local engineering skills and validates affected monorepo consumers.
   `fm-spawn.sh` checks the bound claim before launching or relaunching on any backend.
5. `pr` records the canonical PR URL on the Plane ticket without changing ticket contents or assignment.
   It is not link-only: the binding document records that it also re-applies the implementing lifecycle state, so run it once and before `review`.
   Direct-PR work can register a draft early; no-mistakes work lets its pipeline own PR creation.
6. `review` moves the Plane ticket to In review while preserving the claim.
   `resume` returns it to implementation when corrections are needed.
7. `complete` checks GitHub's merged result and requires an explicit acceptance-verification flag before setting Done.
   Configure `GH_TOKEN` or `GITHUB_TOKEN` for private PR verification.
   This command never merges the PR itself.

Control performs lifecycle synchronization on the existing supervision events; no new always-running polling service is installed.
`sync` repairs a Plane link/state projection after an interrupted update.
External moves to canceled, closed or another unrelated state stop routine synchronization for reconciliation.
Implementation waiting for review remains reserved even when its worker exits.

For multiple projects or repos, use separate private configurations and homes in this initial adapter.
An explicit `--config` is useful for inspection, but automatic spawn validation reads the home's canonical `config/plane.json`.
Do not mix bindings from different project configurations in one home.

## Shared claim mechanics and limits

The remote branch `refs/heads/fm-plane/<hash>` contains an operational `claim.json` record.
The hash includes Plane instance, workspace, project and ticket identity.
`bin/fm_plane/registry.py` is the owner of the remote compare-and-swap mechanism.
It uses an explicit expected Git ref SHA for creation and subsequent writes, preserving history; two concurrent callers cannot both replace the same version successfully.
No local file lock, Plane assignment update or MCP status write is treated as an atomic cross-machine claim.
Exclude `fm-plane/**` branches from product deployment workflows and protect them from automatic branch cleanup.

The registry is coordination among trusted collaborators, not an authorization boundary against someone who can independently rewrite Git refs or modify Plane.
Plane and Git are separate systems; synchronization is recoverable but is not a distributed transaction.
A failed Plane update retains the claim, and Control must retry or reconcile before dispatch.
Lifecycle operations for one execution should be serialized by its owning Control instance.
Remote transport failures may leave a successful write without its response; reread the record before retrying.

The adapter checks the configured readiness label, eligible pickup state, description, existing PR links and native blocked-by/start-after/finish-after prerequisites.
Temporal prerequisites are conservatively required to be complete.
Custom relations and cross-project dependencies require explicit review and a supported mapping before automatic pickup.
The adapter cannot infer dependencies mentioned only in prose; the planning workflow must encode them or Control must stop and clarify.
Manual PRs that were never linked to Plane cannot be discovered by reading the ticket; teammates should attach their PR before starting implementation.
The claim alone does not detect overlapping changes across different tickets; Control must compare shared interfaces and validate downstream packages.

## Recovery

Claims never expire automatically.
After a crash, use `status` and inspect the branch/PR before resuming.
`release` is restricted to executions without a registered PR and requires a preservation acknowledgement and reason.
Keep the reason and preserved-work location in the team handoff before releasing.
Release restores the original Backlog/Todo state recorded at pickup and leaves labels unchanged; removing the readiness label prevents a later new claim.
`transfer` requires confirmation that the previous operative stopped and returns a new execution token for the destination executor.
It retains PR history and invalidates the old token for adapter checks.
It does not revoke a previous worker's independent Git credentials.

An existing-PR transfer needs manual recovery into the existing worktree/branch, following the normal Firstmate recovery procedure.
This initial adapter does not automatically reconstruct a lost remote worktree or bind transferred PR work to a fresh task.
If a brief scaffold fails after binding, preserve the claim and inspect local artifacts before retrying; never delete unlanded work to make retry succeed.

## Verification and provenance

Run `bin/fm-test-run.sh tests/fm-plane.test.sh` with the SDK-enabled `FM_PLANE_PYTHON`.
The suite exercises real Git ref contention and a local MCP protocol fixture without mutating a Plane workspace.
CI runs an additional SDK-enabled lane.
Live At Bryde MCP access, actual project state IDs and end-to-end worker launch against your credentials remain setup-time validation requirements.

The adapter was developed against the official [Plane MCP server](https://github.com/makeplane/plane-mcp-server) resource/action interface and advertised legacy names.
The reference source revision is `ae6bad647aa9cea73d85e9cceab427c16d5c5277`; runtime tool discovery controls which names are used.
The [Pocock skill collection](https://github.com/mattpocock/skills) remains project-owned.
No private At Bryde source, ticket content or credentials are copied into this public fork.
