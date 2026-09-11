# Plane missions in the Control edition

Plane is the shared backlog; each person's Control instance executes selected tickets through the existing Firstmate lifecycle.
This adapter replaces the orchestration role of Pocock's `implement` workflow for Plane tickets while retaining repo-local engineering disciplines.
It does not copy, rewrite or install Pocock's skills.

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

## Setup

Requires Git, Python 3.10+, the optional MCP SDK in `bin/requirements-plane.txt`, and a reachable authenticated Plane MCP server.
Install the optional SDK into a virtual environment and set `FM_PLANE_PYTHON` to that environment's Python executable when launching Firstmate.
The same interpreter must be used for adapter commands.
Each instance needs its own explicit `FM_HOME` and executor name.

Store the following configuration privately at `FM_HOME/config/plane.json`.
Replace example values with actual repository, workspace, project and state identifiers.
No actual At Bryde ticket or state IDs are bundled.

```json
{
  "plane_url": "https://plane.example.com",
  "workspace_slug": "YOUR_WORKSPACE",
  "project_id": "YOUR_PROJECT_UUID",
  "repository_url": "https://github.com/YOUR_ORG/YOUR_MONOREPO",
  "coordination_remote": "git@github.com:YOUR_ORG/YOUR_MONOREPO.git",
  "executor": "mathieu-control",
  "states": {
    "ready": "READY_FOR_AGENT_STATE_UUID",
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

Run `doctor` before configuring state IDs.
It lists the project's actual states and suggests an unambiguous Ready for agent or Ready for agents state.
Missing or duplicate candidates require selecting the intended ID; no fallback to a general backlog state is assumed.
The configured Ready state is the planning team's promise that the ticket has sufficient scope and acceptance criteria.

All colleagues must use the same canonical `plane_url`, workspace, project and `coordination_remote` for the same queue.
Prefer a private coordination repository if even opaque work-item IDs and executor names are sensitive.
The claim records contain no ticket descriptions, API keys or implementation content.
This public Firstmate fork is not an appropriate default for private team execution records.

## Lifecycle

`bin/fm-plane.py --help` and its subcommand help own the command syntax.

1. `list` returns a page of Plane tickets including pagination metadata.
   Control selects an eligible ticket from the authorized scope and reads its requirements.
2. `claim` uses the ticket UUID and a unique request ID, verifies readiness and dependencies, reserves it remotely, then updates Plane to In progress.
   Retries use the same request ID.
3. `bind` creates the ordinary Firstmate brief and a private execution receipt for a local task.
   Control still files the local execution-ledger entry and uses normal `fm-spawn.sh` dispatch with the chosen delivery mode and approval posture.
4. The operative uses repo-local engineering skills and validates affected monorepo consumers.
   `fm-spawn.sh` checks the bound claim before launching or relaunching on any backend.
5. `pr` records the canonical PR URL and adds it to the Plane ticket without changing ticket contents or assignment.
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

The adapter checks configured Ready status, description, existing PR links and native blocked-by/start-after/finish-after prerequisites.
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
