#!/usr/bin/env bash
# Single owner of a ship task's mode-specific "Definition of done" block.
# Sourced by bin/xo-brief.sh, which renders it into a generated ship brief, and by
# bin/xo-promote.sh, which renders it into the ship instructions a promoted scout
# receives. Both paths must hand the worker the same contract: a promoted
# no-mistakes worker that never received the ask-user escalation rule or the
# `--yes` ban is the exact delivery hole this single owner exists to close.
# xo_dod_block <no-mistakes|direct-PR|local-only> <task-id> prints the block on
# stdout with no trailing blank line. The caller validates the mode; an unknown
# mode is refused rather than silently rendered as the pipeline contract.
# The block opens with the fixed machine-readable "Delivery contract: mode=<mode>"
# line that bin/xo-spawn.sh checks a ship brief against.
# This file is also the one owner of what `done:` means per mode. xo_dod_done_line
# prints the single done line a mode accepts (`done: PR {url} checks green` for
# no-mistakes, `done: PR {url}` for direct-PR, `done: ready in branch xo/<id>` for
# local-only) and xo_dod_done_binding prints the paragraph that binds `done:` to
# that line and its evidence and declares any other done line not a done, treated
# as a worker that stopped short. xo_dod_block renders that binding into the
# Definition of done and bin/xo-brief.sh renders the same function into the ship
# status protocol, so the worker reads one binding at the report site and at the
# gate, and neither copy can drift. A no-mistakes worker starts the pipeline
# itself after its implementation commit and reports the commit as a nonterminal
# `working:` line; the brief never offers a done line at the commit, which is the
# false done the binding exists to close.
# This file is the one owner of the no-mistakes `--intent` contract: only the
# brief's `## Captain's intent` subsection plus later captain words, never
# `## XO spec` and never the worker's own tradeoffs.
# The string passed must be self-sufficient - it plus the codebase reconstructs
# roughly the same specification - so a report, decision, or PR the intent
# refers to is written into it as substance, never left as a pointer.
# bin/xo-brief.sh scaffolds those two `# Task` subsections; bin/xo-spawn.sh and
# bin/xo-promote.sh refuse leftover `{TASK}` / `{XO_SPEC}` placeholders
# through the helpers below. Other mentions of `--intent` point here rather than
# restating the rule.
# Every heredoc here stays outside a command substitution: `VAR=$(cat <<EOF ...)`
# breaks parsing of the whole file on Bash 3.2 (tests/xo-brief.test.sh).
# xo_brief_worker_role owns the ship/scout role scope. bin/xo-spawn.sh is its one
# emitter, supplying it to every ship/scout launch brief and never to a
# secondmate charter. Like xo_brief_intent_overlay it is a distinctly titled
# launch section that states its own precedence for XO tasks, so a brief
# that authors its own role wording is superseded rather than duplicated.

xo_brief_worker_role() {
  cat <<'EOF'
# Current worker role contract
When this task works on XO itself, this section supersedes every earlier brief instruction about your role and identity.
When this task works on XO itself, the repository root `AGENTS.md` (also imported by `CLAUDE.md`) is the primary/secondmate supervisor's contract: follow this brief instead of that supervisor contract.
For that XO task, do the assigned work yourself and report to xo; do not adopt the supervisor identity, delegate the task, run fleet supervision, or address the captain.
This exception preserves this brief's safety and authority boundaries and applicable contributor guidance, including `CONTRIBUTING.md` and `xo-coding-guidelines` for XO changes.
Other projects retain their own instructions unchanged.
EOF
}

# Return 0 when a Task subsection still consists only of its scaffold
# placeholder. A missing file and legacy briefs carry no such placeholders.
xo_brief_task_placeholders_present() {  # <file>
  local file=$1 intent spec
  [ -f "$file" ] || return 1
  intent=$(xo_brief_task_heading_body "$file" "## Captain's intent")
  spec=$(xo_brief_task_heading_body "$file" "## XO spec")
  [ "$(printf '%s' "$intent" | tr -d '[:space:]')" = '{TASK}' ] && return 0
  [ "$(printf '%s' "$spec" | tr -d '[:space:]')" = '{XO_SPEC}' ] && return 0
  return 1
}

# Parse an exact ATX heading outside fenced blocks. Body mode prints through
# the next unfenced heading at the same or a higher level; present mode reports
# whether the heading exists.
xo_brief_heading_parse() {  # <file|-> <heading> <body|present>
  local file=$1 heading=$2 mode=$3 input=$1
  if [ "$file" = - ]; then
    input=/dev/stdin
  else
    [ -f "$file" ] || { [ "$mode" = body ]; return; }
  fi
  awk -v heading="$heading" -v mode="$mode" '
    BEGIN {
      target_level = 0
      while (substr(heading, target_level + 1, 1) == "#") target_level++
    }
    {
      line = $0
      scan = line
      spaces = 0
      while (spaces < 3 && substr(scan, 1, 1) == " ") {
        scan = substr(scan, 2)
        spaces++
      }
      marker = substr(scan, 1, 1)
      marker_len = 0
      if (marker == "`" || marker == "~") {
        while (substr(scan, marker_len + 1, 1) == marker) marker_len++
      }
      is_fence = marker_len >= 3
      was_fenced = fenced

      if (is_fence) {
        rest = substr(scan, marker_len + 1)
        if (!fenced) {
          fenced = 1
          fence_marker = marker
          fence_len = marker_len
        } else if (marker == fence_marker && marker_len >= fence_len && rest ~ /^[[:space:]]*$/) {
          fenced = 0
        }
      }

      if (!found && !was_fenced && line == heading) {
        found = 1
        if (mode == "present") next
        grab = 1
        next
      }
      if (mode == "present" || !grab) next
      if (is_fence || was_fenced) {
        print line
        next
      }

      level = 0
      while (substr(scan, level + 1, 1) == "#") level++
      if (level > 0 && level <= target_level && substr(scan, level + 1, 1) ~ /^[[:space:]]?$/) exit
      print line
    }
    END {
      if (mode == "present" && !found) exit 1
    }
  ' "$input"
}

xo_brief_heading_body() {  # <file> <heading>
  xo_brief_heading_parse "$1" "$2" body
}

xo_brief_heading_present() {  # <file> <heading>
  xo_brief_heading_parse "$1" "$2" present >/dev/null
}

xo_brief_task_heading_body() {  # <file> <heading>
  local task
  task=$(xo_brief_heading_body "$1" "# Task")
  printf '%s\n' "$task" | xo_brief_heading_parse - "$2" body
}

xo_brief_task_heading_present() {  # <file> <heading>
  local task
  task=$(xo_brief_heading_body "$1" "# Task")
  printf '%s\n' "$task" | xo_brief_heading_parse - "$2" present >/dev/null
}

xo_brief_marked_captain_words() {  # <task-body>
  printf '%s\n' "$1" | awk '
    match($0, /^[[:space:]]*Captain('\''s (words|ask|intent))?:[[:space:]]*/) {
      words = substr($0, RLENGTH + 1)
      if (words ~ /[^[:space:]]/) print words
    }
  '
}

xo_brief_intent_overlay() {  # <captain-intent>
  cat <<'EOF'

# Current no-mistakes intent contract
This section supersedes every earlier brief instruction about constructing `--intent`, but not later clarifications actually supplied by the captain.
Use the serialized captain intent below plus any later words the captain actually supplied as `--intent`; never include XO specification or other mixed Task content.

## Captain intent authorized for --intent
EOF
  printf '%s\n' "$1"
  cat <<'EOF'

XO-authored constraints, acceptance criteria, implementation details, decisions, and tradeoffs are specification, not captain intent.
The Definition of done's rule that `--intent` must be self-sufficient still governs the string you pass: resolve any report, decision, or PR the intent above refers to into its substance rather than passing the pointer.
EOF
}

# Accept the current two-subsection contract only when both bodies have content;
# briefs predating that contract remain valid when their # Task body has content.
xo_brief_task_content_valid() {  # <file>
  local file=$1 intent spec task has_intent=0 has_spec=0
  [ -f "$file" ] && [ -r "$file" ] || return 1
  xo_brief_task_heading_present "$file" "## Captain's intent" && has_intent=1
  xo_brief_task_heading_present "$file" "## XO spec" && has_spec=1
  if [ "$has_intent" -eq 1 ] || [ "$has_spec" -eq 1 ]; then
    [ "$has_intent" -eq 1 ] && [ "$has_spec" -eq 1 ] || return 1
    intent=$(xo_brief_task_heading_body "$file" "## Captain's intent")
    spec=$(xo_brief_task_heading_body "$file" "## XO spec")
    [ -n "$(printf '%s' "$intent" | tr -d '[:space:]')" ] || return 1
    [ -n "$(printf '%s' "$spec" | tr -d '[:space:]')" ] || return 1
    return 0
  fi
  task=$(xo_brief_heading_body "$file" "# Task")
  [ -n "$(printf '%s' "$task" | tr -d '[:space:]')" ]
}

xo_ask_user_escalation_block() {  # <data-dir> <task-id>
  local data=$1 id=$2
  cat <<EOF
   For a no-mistakes ask-user gate specifically, escalate all ask-user findings as one event plus one snapshot file, using that same shape even when the gate holds only a single ask-user finding: write only the ask-user findings, verbatim and unparaphrased (id, severity, file, line, description, authority), to \`$data/$id/nm-<run>-findings.txt\`, then report the gate with
   \`needs-decision [key=nm-<run>-<step>]: ask-user findings=<id1>,<id2>,... file=$data/$id/nm-<run>-findings.txt\`
   naming every ask-user finding id from that gate. The status line only points at the file; it never restates or summarizes a finding's content.
EOF
}

# The one `done:` line a delivery mode accepts. `{url}` is the worker's fill site
# for the PR's full https:// URL, the same placeholder the brief prose uses.
xo_dod_done_line() {  # <mode> <task-id>
  local mode=$1 id=$2
  case "$mode" in
    no-mistakes) printf 'done: PR {url} checks green\n' ;;
    direct-PR) printf 'done: PR {url}\n' ;;
    local-only) printf 'done: ready in branch xo/%s\n' "$id" ;;
    *)
      echo "error: xo_dod_done_line: unknown delivery mode '$mode'" >&2
      return 1 ;;
  esac
}

# The paragraph binding `done:` to the mode's accepted line and its evidence.
# Rendered by xo_dod_block into the Definition of done and by bin/xo-brief.sh
# into the ship status protocol, so a done line without that evidence is
# declared not a done at both the report site and the gate.
xo_dod_done_binding() {  # <mode> <task-id>
  local mode=$1 id=$2 line evidence not_done
  line=$(xo_dod_done_line "$mode" "$id") || return 1
  case "$mode" in
    no-mistakes)
      evidence='a PR whose checks are green, named by its full https:// URL'
      not_done='A local commit with passing local checks, a started pipeline run, or an open PR still waiting on CI'
      ;;
    direct-PR)
      evidence='an open PR, named by its full https:// URL'
      not_done='A local commit or a pushed branch with no PR'
      ;;
    local-only)
      evidence="your work committed on branch \`xo/$id\` as a clean fast-forward onto the default branch"
      not_done='Uncommitted work or a branch that no longer fast-forwards'
      ;;
  esac
  cat <<EOF
Done is bound to this task's delivery mode: the only \`done:\` line that counts is \`$line\`, and its evidence is $evidence.
$not_done is not done; a \`done:\` line without that evidence is not a done, and xo treats it as a worker that stopped short of delivery, not as finished work.
EOF
}

xo_dod_block() {  # <mode> <task-id>
  local mode=$1 id=$2 binding
  binding=$(xo_dod_done_binding "$mode" "$id") || {
    echo "error: xo_dod_block: unknown delivery mode '$mode'" >&2
    return 1
  }
  case "$mode" in
    direct-PR)
      cat <<EOF
# Definition of done
Delivery contract: mode=direct-PR
This task ships **direct-PR**: you raise the PR yourself, without the no-mistakes pipeline.
$binding
When it is implemented and committed, push your branch and open a PR with \`gh-axi\`, then append \`done: PR {url}\` to the status file and stop.
Do NOT run /no-mistakes. The configured merge authority decides whether to merge the PR; xo relays the outcome.
EOF
      ;;
    local-only)
      cat <<EOF
# Definition of done
Delivery contract: mode=local-only
This task ships **local-only**: no remote, no PR, no pipeline.
$binding
The task is complete only when committed on your branch \`xo/$id\`. Do NOT push, do NOT open a PR, do NOT merge.
Keep your branch a clean fast-forward onto the current default branch - if \`main\` has advanced, rebase onto it so the eventual merge stays a fast-forward.
When it is implemented and committed, append \`done: ready in branch xo/$id\` to the status file and stop.
The configured merge authority approves the ready branch, then xo merges it into local \`main\` through the guarded fast-forward path.
EOF
      ;;
    no-mistakes)
      cat <<EOF
# Definition of done
Delivery contract: mode=no-mistakes
This task ships **no-mistakes**: you validate and ship the PR through the no-mistakes pipeline yourself.
$binding
Commit the implementation on your branch, append the nonterminal \`working: implementation committed, starting no-mistakes\` line, and start /no-mistakes in that same turn to validate and ship the PR.
Do not stop at the commit and do not wait for xo to tell you to start the pipeline: the commit is a milestone, never a gate, and there is no done line for it.
If an instruction to run /no-mistakes reaches you while your run is already active, reattach to that run; never start a second one.

You drive no-mistakes by responding to its gates, not by implementing fixes.
Follow the guidance no-mistakes itself provides for the mechanics: it loads when you invoke /no-mistakes, and \`no-mistakes axi run --help\` plus the \`help\` lines in each \`axi\` response are authoritative and version-matched to the installed binary.
When starting no-mistakes, pass \`--intent\` as only this brief's \`## Captain's intent\` subsection plus any later words the captain actually said.
For a legacy brief with no such subsection, include only words explicitly labeled \`Captain:\`, \`Captain's words:\`, \`Captain's ask:\`, or \`Captain's intent:\`; never copy its mixed \`# Task\` wholesale. If it has no provenance-marked captain words, stop and ask xo instead of starting no-mistakes.
Do not include \`## XO spec\`, later XO build constraints, or your own decisions and tradeoffs.
The \`--intent\` string you pass must be self-sufficient: that string plus the codebase must let a reader reconstruct roughly the same specification, without depending on a separate report, a PR, or context that lives only in this conversation.
When the captain's intent refers to a report, decision, or PR ("do items 1, 2, 3, and 7 of the report"), write the substance of the referenced items into \`--intent\` in the captain's terms, not only the pointer; that substance is the captain's ask by reference, while XO's build instructions and your own decisions still stay out.
This replaces the no-mistakes skill's advice to enrich \`--intent\` with decisions and tradeoffs; that advice does not apply to XO-dispatched work.
Do not hand-edit, commit, or fix findings yourself while a run is active - the pipeline applies every fix.

One drive call blocks until the next gate or outcome, which routinely outlives what your harness lets a single command run: Claude Code kills a command at ten minutes maximum, while one fix round is capped around thirty minutes and up to three rounds chain.
So background the drive call and poll \`no-mistakes axi status\` from a separate call instead of sitting in one blocking hold your harness will kill.
Where a harness's own command limit is not established, assume it bounds commands and use that same background-and-poll shape.
A killed or timed-out call is never evidence the daemon died: the daemon accepts your response immediately and runs the round in the background, so the call was only ever waiting for a read while the run kept working.
Reattach and keep going rather than reporting the pipeline blocked; rule 7 owns the checks that decide when a pipeline block is real.

Two xo-specific rules layer on top of that guidance:
- ask-user findings are never yours to answer: escalate to xo using rule 6's ask-user format and stop.
  XO applies \`ask-user-authority\` and obtains any required captain decision.
  When the decision comes back, feed it to the gate with \`no-mistakes axi respond\` and let the pipeline apply it - do not route the question to "the user" or implement the fix yourself.
- NEVER pass \`--yes\` (or \`-y\`) to \`no-mistakes axi run\` or \`no-mistakes axi respond\`. It is banned fleet-wide.
  It auto-resolves every gate including ask-user findings with no escalation, and answering your own ask-user finding is a hard rule violation.

After /no-mistakes reports CI green (the CI-ready return point - do not wait for it to keep monitoring in the background until merge), append \`done: PR {url} checks green\` and stop. You are finished.
EOF
      ;;
    *)
      echo "error: xo_dod_block: unknown delivery mode '$mode'" >&2
      return 1 ;;
  esac
}
