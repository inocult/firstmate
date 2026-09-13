# The bin/ toolbelt

The XO drives these; interactive entrypoints work by hand too, while `*-lib.sh` files are sourced helpers.
Each row is one purpose clause only: the script's own header comment is the authoritative description of its behavior, flags, and contracts, so read the header before first use.
If you have changed away from the XO home in an interactive shell, invoke these scripts by absolute path through the repo's `bin/` directory; the scripts self-locate internally after they start.
The shared no-mistakes gate refusal for fleet lifecycle entrypoints is summarized in [architecture.md](architecture.md#no-mistakes-gate-authority-boundary), while `docs/sessionstart-nudge.md` covers the silent session-open hook use; `xo-gate-refuse-lib.sh`'s header owns its exact contract.

| Script                   | Purpose                                                                              |
| ------------------------ | ------------------------------------------------------------------------------------ |
| `xo-session-start.sh`    | Compose lock, bootstrap, and wake drain into the single ordered session-start digest |
| `xo-sessionstart-nudge.sh` | Print the native session-start hook nudge when the primary has not already run the digest |
| `xo-sessionstart-run.sh` | Route a native session-open hook to the full digest, a context re-emit, or the nudge |
| `xo-operational-input.sh` | Construct and parse the canonical cross-language operational-input protocol |
| `xo-bootstrap.sh`        | Detect toolchain and fleet problems, run the locked session-start sweeps, and install approved tools |
| `xo-startup-network.sh`  | Run session start's network checks and inactive-outcome scan off its blocking path, retaining reports and durable findings |
| `xo-fleet-sync.sh`       | Refresh project clones with safe fast-forwards, self-heals, `STUCK:` reports, branch pruning, and bounded recovery from an orphaned `.git/packed-refs.lock` |
| `xo-fleet-snapshot.sh`   | Print structured fleet snapshot JSON and refresh only its parent-side remote-ledger cache (schema `xo-fleet-snapshot.v1`) |
| `xo-home-summary-refresh.sh` | Atomically publish this home's structured summary ledger                         |
| `xo-fleet-view.sh`       | Render the fleet snapshot as a human Markdown view                                   |
| `xo-bearings-snapshot.sh` | Project the bounded remote-ledger fleet snapshot to compact TOON; `--include-prs` adds live GitHub enrichment |
| `xo-bearings-board.sh`   | Build and arm the stable interactive `/bearings lavish` fleet board                  |
| `xo-secondmate-reconcile.sh` | Queue Bearings reconcile requests for later supervision delivery and ask each mismatched home through its durable inbox with a per-home cooldown |
| `xo-update.sh`           | Fast-forward-only self-update of XO and local or remote secondmate homes, classifying every live mate left on the target commit for restart or fallback nudge |
| `xo-secondmate-restart.sh` | Persist open conversational work, then restart eligible second mates or report the fallback outcome |
| `xo-secondmate-restart-lib.sh` | Shared second-mate restart capability and persistence-request contract |
| `xo-on.sh`               | Execute one tracked XO command in a configured remote secondmate home, using its job worker except for the doctor bootstrap |
| `xo-remote-job-lib.sh`   | Shared bounded remote job queue, worker readiness, LaunchAgent contract, and filesystem-composed PATH |
| `xo-remote-job-worker.sh` | Long-lived remote queue worker for tracked `xo-*.sh` commands in the account runtime |
| `xo-remote-job-reap-orphans.sh` | Stop remote job workers left running by a pruned code root, never one whose checkout still exists |
| `xo-remote-doctor.sh`    | Check, and with `--fix` repair, one remote account's second-mate readiness (remote job worker, Herdr, Aqua launch agents, PATH, and required tools) |
| [`xo-backlog-handoff.sh`](../bin/xo-backlog-handoff.sh) | Move queued backlog items into a secondmate home; its header owns route-specific wake outcomes and retries |
| `xo-backlog-receive.sh`  | Idempotently ingest one confined remote handoff outbox through tasks-axi             |
| `xo-captain-hold.sh`     | Hold tasks for the captain, record the captain's answers, gate investigation completion, and report record divergence between the status log and the backlog |
| `xo-decision-hold.sh`    | One-release compatibility shim mapping the retired decision commands onto xo-captain-hold.sh |
| `xo-brief.sh`            | Scaffold ship (explicit `--mode`), scout, secondmate-charter, and Herdr-lab briefs, with Captain's intent and XO spec subsections on ship/scout |
| [`xo-dod-lib.sh`](../bin/xo-dod-lib.sh) | Own ship/scout worker role scope, ship definitions of done, and the no-mistakes `--intent` contract |
| `xo-herdr-lab.sh`        | Provision and guardedly operate an isolated, never-default Herdr lab session         |
| `xo-herdr-lab-viewer.py` | The pty engine behind `xo-herdr-lab.sh viewer`: one real foreground Herdr client on a non-zero window grid |
| `xo-install-herdr.sh`    | Install CI's exact-version Herdr pin with official asset URL, SHA-256, and protocol checks |
| `xo-install-treehouse.sh`| Install CI's exact-version Treehouse pin for real-Herdr E2E that needs spawn worktrees |
| `xo-herdr-ci-cleanup.sh` | Snapshot and tear down only job-owned `xo-lab-*` sessions in the Herdr CI lane       |
| `xo-test-run.sh`         | Behavior-test runner: selection, portable lanes, bounded concurrency, budgets, coverage guard, timing/JSON; refuses to execute in the repository primary checkout when `XO_TASK_ID` marks a task worker |
| `xo-test-isolation-proof.sh` | Concurrent isolation harness and portable candidate set owner |
| `xo-ensure-agents-md.sh` | Ensure a project's real `AGENTS.md`, its `CLAUDE.md` `@AGENTS.md` pointer, and self-governance guidance (explicit project mark documented in the helper's header and help) |
| `xo-guard.sh`            | Warn on primary-checkout tangles, main-session pending wakes, and unhealthy supervision |
| `xo-primary-scope-lib.sh` | Shared marker-or-plain-checkout primary-home predicate for tracked hooks             |
| `xo-session-lock-lib.sh` | Shared session-lock harness identity (ancestry walk and holder liveness) for xo-lock.sh and the Claude Stop auto-arm |
| `xo-claude-stop-autoarm.sh` | Claude Stop `asyncRewake` hook owning tokenless watcher continuity with single-flight exit-2 rewake (docs/watcher-continuity.md) |
| `xo-turnend-guard.sh`    | Shared primary turn-end guard predicate so no turn ends blind (docs/turnend-guard.md) |
| `xo-turnend-guard-grok.sh` | Grok Stop-hook adapter for the primary turn-end guard                              |
| `xo-kimi-turnend-hook.sh` | Surgically install or remove Kimi's guarded global crew turn-end hook                |
| `xo-arm-pretool-check.sh` | Stable PreToolUse transport for the watcher-arm command policy (docs/arm-pretool-check.md) |
| `xo-arm-command-policy.mjs` | Semantic owner of the watcher-arm PreToolUse policy (docs/arm-pretool-check.md)   |
| `xo-subagent-pretool-check.sh` | Primary-home delegation-shape PreToolUse guard (docs/subagent-guard.md) |
| `xo-supervision-instructions.sh` | Render the session-start primary-harness supervision block or the one-line repair instruction |
| `xo-home-seed.sh`        | Transactionally provision a local secondmate home and maintain `data/secondmates.md` |
| `xo-remote-home-seed.sh` | Register and provision a whole secondmate home on an SSH-reachable host              |
| `xo-remote-readiness-lib.sh` | Shared remote second-mate readiness gate: check and, when needed, repair then re-check through `xo-remote-doctor.sh` |
| [`xo-project-origin-lib.sh`](../bin/xo-project-origin-lib.sh) | Accepted origin-form owner shared by both remote provisioning boundaries |
| `xo-spawn.sh`            | Spawn crewmates, scouts, `id=repo` batches, and secondmates on the resolved harness and runtime backend |
| `xo-backend.sh`          | Runtime-backend selection, meta helpers, selector resolution, and operation dispatch |
| `xo-backend-hometag-lib.sh` | Shared per-installation home-tag derivation for zellij tab and cmux workspace titles |
| `xo-composer-lib.sh`     | Single fleet-wide owner of composer shapes, capability-aware screen classification, and verdicts |
| `xo-agent-process-lib.sh` | Backend-neutral harness-process name classifier shared by the tmux and herdr adapters |
| `backends/tmux.sh`       | Verified tmux session-provider adapter                                               |
| `backends/herdr.sh`      | Herdr session-provider adapter with its own required CI lane                         |
| `backends/zellij.sh`     | Experimental zellij session-provider adapter                                         |
| `backends/orca.sh`       | Experimental Orca backend adapter owning both worktree and terminal                  |
| `backends/cmux.sh`       | Experimental cmux session-provider adapter                                           |
| `xo-config-push.sh`      | Push declared inherited local material to live local or remote secondmates and send the placement-specific config reread when changed |
| `xo-project-mode.sh`     | Resolve a project's registered delivery posture from `data/projects.md` for fleet sync and home seeding |
| `xo-merge-local.sh`      | Fast-forward a `local-only` project's local default branch after approval            |
| `xo-review-diff.sh`      | Review a crewmate branch or resolved PR head against the authoritative base          |
| `xo-marker-lib.sh`       | Compatibility entry point for the from-xo carrier owned by `xo-operational-input.sh` |
| `xo-task-inbox-lib.sh`   | Single owner of durable steering-inbox records, acknowledgement, doorbells, and the delivery-attempt ladder |
| `xo-pending-reply-lib.sh` | Parent-owned secondmate pending-reply expectations, recovery, and keyed escalation lifecycle |
| `xo-secondmate-report.sh` | Optional helper that resolves the parent channel itself and appends a correlated status or document-pointer report |
| `xo-extension.mjs`       | Bind, inspect, verify, and strictly invoke trusted external process-event adapter packages |
| `xo-extension-launch-barrier.mjs` | Publish one exact static core-owned invocation group before package code runs |
| `xo-extension.sh`        | Expose extension binding commands through the tracked shell and remote-home command boundary |
| `xo-procevent.sh`        | Register, supervise, capture, classify, acknowledge, and safely retire built-in or explicitly bound process-event sources |
| `xo-procevent-remote-reply.sh` | Relay the remote-secondmate status stream through non-destructive process-event deltas |
| `xo-procevent-quota.sh`  | Wake XO when tracked quota drops below a threshold, is exhausted, or cannot be polled |
| `xo-procevent-when.sh`   | Fire a trust-bound deterministic action at most once when its registered condition holds, then wake with the outcome |
| `xo-gate-refuse-lib.sh`  | Shared no-mistakes gate-context refusal for fleet lifecycle entrypoints               |
| `xo-watch-arm.sh`        | Verified home-scoped watcher arm wrapper with loud cycle endings and bounded lifecycle ledger |
| `xo-watch-checkpoint.sh` | Run one bounded foreground watcher checkpoint for Codex-style supervision            |
| `xo-watch.sh`            | Singleton-safe watcher: absorb benign wakes, detect stalled local-secondmate wake queues, and exit on actionable ones |
| `xo-inactive-reconcile.sh` | Reconcile long-inactive direct crewmate terminal outcomes without forge access |
| `xo-afk-contract.sh`     | Own the away-posture record: schema, mandate-clause fields and never-set scan, refusal naming the missing part, read-back, entry announcement, archive |
| `xo-afk-start.sh`        | Run the common sourceable away-mode daemon entry in the foreground                      |
| `xo-afk-launch.sh`       | Own away-mode entry (read-back, confirm, record), exit, rollback, and any backend terminal lifecycle |
| `xo-afk-return.sh`       | Own deterministic return shutdown, the return brief, catch-up evidence, and the xo-actionable blocker gate |
| `xo-supervisor-target-lib.sh` | Resolve the shared supervisor target and backend for the daemon and launcher       |
| `xo-supervise-daemon.sh` | Presence-gated away-mode sub-supervisor: self-handle routine wakes, guard injection by the detected primary harness, escalate batched digests, alert on failed delivery |
| `xo-crew-state.sh`       | Print one deterministic current-state line for a crew                                |
| `xo-nm-run-lib.sh`       | Single owner of shared no-mistakes run-attribution primitives and rules             |
| `xo-tangle-lib.sh`       | Shared default-branch resolution and primary-checkout tangle classification          |
| `xo-timeout-lib.sh`      | Single owner of hard-bounded command execution and its fallback watchdog |
| `xo-timing-lib.sh`       | Single owner of the deferred network stage's per-step elapsed-time records, inert unless a run asks for them |
| `xo-supervision-lib.sh`  | Shared in-flight-work-without-fresh-watcher-beacon predicate                         |
| `xo-ff-lib.sh`           | Shared guarded fast-forward helper for origin pulls and secondmate syncs             |
| `xo-lock-lib.sh`         | Shared "is this git lock provably abandoned?" proof used by teardown and fleet-sync   |
| `xo-config-inherit-lib.sh` | Shared primary-to-secondmate inherited local-material propagation and config-reread delivery |
| `xo-tasks-axi-lib.sh`    | Shared backlog-backend selector and `tasks-axi` compatibility probe                  |
| `xo-backlog-transition-lib.sh` | Pair task-record changes with their backlog transitions and replay interrupted closes |
| `xo-quota-axi-lib.sh`    | Shared `quota-axi` compatibility floor and quota snapshot schema validation           |
| `xo-quota-choose.sh`     | Choose the first candidate with known positive quota from an ordered harness:model list |
| `xo-vendor-auth-probe.sh`| Run one hard-bounded, non-destructive authentication probe of a named vendor CLI and report the fact |
| `xo-wake-drain.sh`       | Present and acknowledge the current actor's claimed wake rows alongside status, outcome-backstop, decision, divergence, recovery, and supervision checks |
| `xo-wake-grant.sh`       | Serialize Pi supervision-branch wake-row claim activation, publication, release, and deactivation |
| `xo-wake-lib.sh`         | Shared durable wake queue, recovery generations, portable locks, and watcher identity/health helpers |
| `xo-classify-lib.sh`     | Shared wake classification, durable keyed-decision folds and scans, unread status selection, and bounded latest-event snapshots |
| `xo-send.sh`             | Steer a task via a durable inbox record plus doorbell, or send a supported key or typed harness invocation through the recorded backend |
| `xo-branch-prompt.sh`    | Emit the Pi supervision branch's byte-stable system prompt ([pi-supervision-branch.md](pi-supervision-branch.md)) |
| `xo-branch-outcome.sh`   | Own the supervision branch's append-only outcome store, cursors, bounded status-coverage indexes, and session-start replay |
| `xo-lease.sh`            | Claim, release, inspect, and sweep per-task supervision leases                       |
| `xo-lease-lib.sh`        | One owner of the supervision lease contract and the main-only role-partition guards  |
| `xo-control.sh`          | Agent lifecycle control plane: allowlisted `interrupt`, `exit`, and transactional `relaunch` verbs for an exact task id ([agent-control.md](agent-control.md)) |
| `xo-control-lib.sh`      | One executable owner of the control-plane verb allowlist, per-harness interrupt/exit mechanics, and per-backend capability |
| `xo-busy-lib.sh`         | Single owner of the semantic busy-state contract: verdicts, source attribution, and per-harness sources |
| `xo-busy-event.sh`       | The only writer of a task's semantic busy-state record and native-harness progress marker; arms an incarnation and applies lifecycle events |
| `xo-tmux-lib.sh`         | Shared tmux pane primitives for composer capture, verified submit, and the submit-time busy check |
| `xo-peek.sh`             | Print a bounded tail of a crewmate endpoint                                          |
| `xo-check-register.sh`   | Bind an intentional custom watcher check to its current bytes                       |
| `xo-check-unregister.sh` | Retire a custom watcher check and its trust binding by validated task id            |
| `xo-check-lib.sh`        | Validate custom-check registrations and prepare private execution snapshots          |
| `xo-tool-update-check.sh` | Report watched tooling with an update available, and updates installed but left inert by PATH order |
| `xo-pr-lib.sh`           | Own canonical task and PR validation plus private atomic PR-poll publication, merge-notification identity, and retirement |
| `xo-pr-poll.sh`          | Provide the byte-static watcher program for validated PR/MR-poll sidecars           |
| `xo-pr-check.sh`         | Record validated `pr=` and `pr_head=` values, then atomically arm a static merge poll |
| `xo-pr-merge.sh`         | Record PR metadata, merge a task's canonical full GitHub or GitLab URL, then refuse an outcome it cannot prove landed or queued |
| `xo-merge-outcome-lib.sh` | Publish a confirmed merge's durable, role-routed supervision outcome                 |
| `xo-parent-channel-lib.sh` | Resolve a secondmate home's parent channel and append a captain-facing outcome line to it at most once |
| `xo-promote.sh`          | Promote a scout task in place to a protected ship task with an explicit delivery mode, and write the ship instructions carrying that mode's definition of done |
| `xo-teardown.sh`         | Fail-closed teardown: return landed ship worktrees, require completed scout deliverables, retire secondmate homes |
| `xo-harness.sh`          | Detect the running harness, resolve crew or secondmate harness, model, and effort, and validate the native-only `ultra` effort |
| `xo-lock.sh`             | Per-home XO session lock                                                      |
| `xo-x-lib.sh`            | Shared Relay config, relay, and reply-threading helpers                              |
| `xo-x-poll.sh`           | One bounded Relay poll: stash newly offered mentions and emit their once-only wake   |
| `xo-x-reply.sh`          | Post or dry-run preview a composed Relay reply or follow-up                          |
| `xo-x-dismiss.sh`        | Dismiss a skipped Relay mention at the relay without replying                        |
| `xo-x-link.sh`           | Link a spawned task to its originating Relay mention in task meta                    |
| `xo-x-followup.sh`       | Detect, post, and cap completion follow-ups for a Relay-linked task                  |
| `xo-public-followup-lib.sh` | Shared Relay gate, open-loop registry state, expiry classification, locking, and private transport paths |
| `xo-public-followup.sh`  | Reconcile and deliver typed public commitments, then rechain or explicitly retire their retained loops |
| `xo-public-followup-emit.sh` | Report one typed terminal work result into the home that owes the public reply, or stage it when that home is on another machine |
| `xo-public-followup-collect.sh` | Read and retire the typed terminal results a remote work home staged for the home that owes the public reply |
| `xo-inbox.sh`            | The captain's out-of-band capture surface: queue a note, dictate one, read status, ask a side question |
| `xo-mail.sh`             | General-purpose mail plane: read unseen IMAP mail, send one SMTP message, or surface new mail as a `check` wake via `poll` (configuration in the home's gitignored `.env`) |
| `xo-mail.py`             | The IMAP/SMTP engine behind `xo-mail.sh` |
| `xo-mail-check.sh`       | Standing received-mail poll: `arm` registers a watcher check that runs `xo-mail.sh poll` on the watcher cadence (new mail still wakes via the poll; the check's own line also wakes unless the poll is a proven no-op), `disarm` removes it |
| `xo-voice-relay.py`      | Hold the spoken conversation on this host, answer from the records, and hand real work to `xo-inbox.sh` ([voice-relay.md](voice-relay.md)) |
| `xo-voice-client.py`     | The laptop end of the spoken interface: capture, playback, and turn timing over SSH; audio devices unverified |
| `xo_voice_frame.py`      | The wire format both machines share, copied to the laptop beside the client          |
| `xo_voice_records.py`    | What a spoken answer may read, and the handover that queues real work                |
