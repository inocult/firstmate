---
name: breach
description: Implement a selected ticket through a claimed Firstmate operative, adapting Matt Pocock's implement workflow to isolated worktrees and supervised PR delivery.
metadata:
  internal: true
---

# Breach

Adapted from Matt Pocock's `skills/engineering/implement/SKILL.md`, retrieved with blob SHA `7a0b11f5f4fe9505ea5c7983c3083ba1bf754f69`.
Upstream: https://github.com/mattpocock/skills/blob/main/skills/engineering/implement/SKILL.md
The upstream MIT notice is preserved in `LICENSE` beside this file.
This adaptation changes orchestration and branch custody; it retains the engineering sequence.

## Control entrypoint

`/breach PLAT-27` means implement that existing ticket, not enable ongoing queue pickup.
With no ticket, use the one already clearly selected in the conversation; otherwise ask which ticket to implement.
Overwatch may invoke Breach for a selected ticket within its active recorded policy.
Do not install a competing coordinator skill named `implement` or call upstream `/implement` recursively.

Load `plane-missions` and follow its claim, binding, worker dispatch and delivery procedures.
[`docs/tracker-binding.md`](../../../docs/tracker-binding.md) owns which surface performs each ticket operation named here and which operations no surface performs.
Resolve a display identifier such as `PLAT-27` to the ticket's UUID through the surface the binding document names for that operation, and verify the configured project and implementation repository before claiming.
Read the ticket and its acceptance criteria; the claim itself verifies the readiness label, pickup state and blocking edges as the binding document states.
If already claimed by this executor, reconcile and resume its existing task/PR rather than start another; another executor's claim is not available work.
Record request ID before claim and reuse it after interruption.
A successful claim is the only entry to creating the local task and isolated worktree.
Use the existing Firstmate backlog, brief, harness/profile and spawn procedures; Control does not implement the project directly.
Include the following engineering contract in the operative's brief.

## Operative engineering contract

Implement the claimed scope and acceptance criteria in the assigned worktree.
Discover applicable project/package instructions and repo-local engineering skills.
Use Pocock's TDD discipline where appropriate at agreed seams; run typechecking and focused tests regularly.
Run the project's complete required validation before delivery, including affected monorepo consumers; when the configured pipeline owns validation, submit it there and consume its results rather than launch duplicate gates.
Perform local self-checks and return the tested change to Control for the separate review stage.
Do not treat implementation-session self-review as independent approval.

Commit to the assigned implementation branch under the selected delivery mode.
This replaces upstream's assumption that the user's current branch is the implementation branch.
If no-mistakes owns commits or branch delivery during an active run, preserve that custody and follow its procedure.
Missing engineering skills must be reported; use available project guidance without silently downloading or replacing skills.
Material scope questions return to Control; routine implementation decisions stay with the operative.
Return commit, validation and review evidence plus remaining blockers through Firstmate's supervisor protocol.

## Delivery

Control registers the canonical PR, supervises corrections and preserves the shared claim during review.
Run the repo's code-review skill in a fresh reviewer context using the configured reviewer profile; a different verified model may be selected without changing that skill.
Provide the immutable reviewed head SHA, base/merge-base SHA, exact ticket/spec and repo standards; keep Standards and Spec findings separate.
The reviewer reports findings without editing the implementation branch; the original operative fixes that same branch and a new head requires refreshed review evidence.
When the selected no-mistakes pipeline already supplies the required independent review, reuse that stage and its evidence rather than start a competing review loop.
A model change provides another perspective, not a different GitHub identity or merge authority.
Keep PR author, human assignee, executor, reviewer and merger distinct.
Only a verified merge and accepted criteria permit the ticket's transition to the done lifecycle state.
Breach itself supplies no additional merge permission, and a stopped operative is not completion.
