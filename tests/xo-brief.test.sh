#!/usr/bin/env bash
# Behavior tests for bin/xo-brief.sh.
#
# Regression coverage for the heredoc-in-command-substitution parse bug (issues
# #166, #958, #1069). Building a variable with `VAR=$(cat <<EOF ... EOF)` is
# unsafe on Bash 3.2 (macOS /bin/bash): the lexer scans for the matching `)` of
# the command substitution textually and tracks quote state through the heredoc
# body, so a single apostrophe, unbalanced quote, or unbalanced paren anywhere
# in that body breaks parsing of the *entire rest of the script* - `bash -n`
# fails, not just the generated brief. The DOD and Herdr-section builders now
# use `IFS= read -r -d '' VAR <<EOF || true` instead, which removes the `$(...)`
# wrapper and eliminates the whole defect class regardless of future prose.
# test_no_heredoc_in_command_substitution guards that structure directly.
# Ambient `bash -n` here is Bash 5 and cannot see the bug, so the real
# cross-version enforcement lives in the macos-stock-bash CI job.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(xo_test_tmproot xo-brief)
BRIEF_HOME="$TMP_ROOT/home"
mkdir -p "$BRIEF_HOME/data"

# The script itself must always parse under the ambient bash. That is Bash 5 in
# CI and locally, where the issue #958/#1069 parser bug does not fire, so this
# is a weak guard on its own; test_no_heredoc_in_command_substitution and the
# macos-stock-bash CI job carry the real cross-version enforcement.
test_script_parses() {
  local out rc
  out=$(bash -n "$ROOT/bin/xo-brief.sh" 2>&1); rc=$?
  expect_code 0 "$rc" "bash -n bin/xo-brief.sh must parse cleanly (got: $out)"
  [ -z "$out" ] || fail "bash -n bin/xo-brief.sh emitted unexpected output: $out"
  pass "xo-brief.sh: bash -n succeeds"
}

# Structural class guard (issues #166, #958, #1069): never build a variable by
# wrapping a heredoc in a command substitution (`VAR=$(cat <<EOF ... EOF)`).
# That construct is what breaks Bash 3.2 parsing, and pinning one historical
# apostrophe phrase (as the old test did) missed the #945 reintroduction. This
# guards the *shape* directly against the whole file, so any future DOD or
# section builder that reintroduces the class fails here regardless of prose.
test_no_heredoc_in_command_substitution() {
  local unsafe safe
  unsafe="$TMP_ROOT/heredoc-in-substitution.sh"
  safe="$TMP_ROOT/plain-heredoc.sh"
  # shellcheck disable=SC2016 # Literal shell fixtures must remain unexpanded.
  printf '%s\n' 'value=$(' '  cat <<EOF' 'body' 'EOF' ')' > "$unsafe"
  # shellcheck disable=SC2016 # Literal shell fixtures must remain unexpanded.
  printf '%s\n' 'cat <<EOF' '$(' '  cat <<INNER' 'INNER' ')' 'EOF' > "$safe"
  if no_heredoc_in_command_substitution "$unsafe"; then
    fail "structural guard accepted a multiline heredoc nested in a command substitution"
  fi
  no_heredoc_in_command_substitution "$safe" \
    || fail "structural guard treated heredoc body prose as shell structure"
  no_heredoc_in_command_substitution "$ROOT/bin/xo-brief.sh" \
    || fail "xo-brief.sh wraps a heredoc in a command substitution (breaks Bash 3.2 parsing)"
  pass "xo-brief.sh: no heredoc is nested inside a command substitution (Bash 3.2 parse-safe)"
}

no_heredoc_in_command_substitution() {
  perl - "$1" <<'PERL'
use strict;
use warnings;

my $path = shift;
open my $source, '<', $path or die "$path: $!\n";
my @frames;
my @heredocs;
my $quote = '';
my $line_number = 0;

while (my $line = <$source>) {
  $line_number++;
  if (@heredocs) {
    my $candidate = $line;
    $candidate =~ s/\r?\n\z//;
    $candidate =~ s/^\t+// if $heredocs[0]{strip_tabs};
    shift @heredocs if $candidate eq $heredocs[0]{delimiter};
    next;
  }

  my $length = length $line;
  for (my $i = 0; $i < $length; $i++) {
    my $char = substr($line, $i, 1);
    if ($quote eq "'") {
      $quote = '' if $char eq "'";
      next;
    }
    if ($char eq '\\') {
      $i++;
      next;
    }
    if ($quote eq '"' && $char eq '"') {
      $quote = '';
      next;
    }
    if ($char eq "'" && $quote eq '') {
      $quote = "'";
      next;
    }
    if ($char eq '"' && $quote eq '') {
      $quote = '"';
      next;
    }
    if ($char eq '#' && $quote eq '' && ($i == 0 || substr($line, $i - 1, 1) =~ /[\s;|&()]/)) {
      last;
    }
    if ($char eq '$' && substr($line, $i + 1, 1) eq '(') {
      push @frames, { depth => 1, quote => $quote };
      $quote = '';
      $i++;
      next;
    }
    if (@frames && $quote eq '' && $char eq '(') {
      $frames[-1]{depth}++;
      next;
    }
    if (@frames && $quote eq '' && $char eq ')') {
      $frames[-1]{depth}--;
      if ($frames[-1]{depth} == 0) {
        my $frame = pop @frames;
        $quote = $frame->{quote};
      }
      next;
    }
    next unless $quote eq '' && $char eq '<' && substr($line, $i + 1, 1) eq '<';
    if (@frames) {
      print STDERR "$path:$line_number\n";
      exit 1;
    }

    my $j = $i + 2;
    my $strip_tabs = substr($line, $j, 1) eq '-';
    $j++ if $strip_tabs;
    $j++ while substr($line, $j, 1) =~ /[ \t]/;
    my $delimiter = '';
    my $delimiter_quote = '';
    for (; $j < $length; $j++) {
      my $token = substr($line, $j, 1);
      if ($delimiter_quote) {
        if ($token eq $delimiter_quote) {
          $delimiter_quote = '';
        } elsif ($token eq '\\' && $delimiter_quote eq '"') {
          $j++;
          $delimiter .= substr($line, $j, 1);
        } else {
          $delimiter .= $token;
        }
        next;
      }
      if ($token eq "'" || $token eq '"') {
        $delimiter_quote = $token;
        next;
      }
      if ($token eq '\\') {
        $j++;
        $delimiter .= substr($line, $j, 1);
        next;
      }
      last if $token =~ /[\s;|&()<>]/;
      $delimiter .= $token;
    }
    push @heredocs, { delimiter => $delimiter, strip_tabs => $strip_tabs };
    $i = $j - 1;
  }
}

exit 0;
PERL
}

test_help_includes_entire_header() {
  local help
  help=$("$ROOT/bin/xo-brief.sh" --help)
  assert_contains "$help" "Refuses to overwrite an existing brief." "xo-brief.sh --help omitted its header terminator"
  pass "xo-brief.sh: --help renders the complete header"
}

# Registry with one project per delivery mode. xo-brief.sh no longer reads it -
# the ship mode arrives as an explicit flag - so this fixture exists to prove the
# scaffold ignores the registered posture (test_ship_mode_is_explicit_not_registry).
write_registry() {
  local home=$1
  mkdir -p "$home/data"
  cat > "$home/data/projects.md" <<'EOF'
- direct-proj [direct-PR] - fixture for direct-PR mode (added 2026-07-01)
- local-proj [local-only] - fixture for local-only mode (added 2026-07-01)
EOF
}

# xo-brief.sh must exit 0 and produce a brief with no unreplaced shell
# metacharacter corruption for every ship delivery mode. This also guards
# against any *new* unescaped apostrophe or unbalanced quote later added to
# one of these DOD blocks, since a broken heredoc corrupts or empties the
# generated brief content, not just the script's own syntax.
test_ship_modes_generate_clean_briefs() {
  local home id mode brief status
  home="$TMP_ROOT/ship-home"
  write_registry "$home"

  for id_mode in "brief-nomistakes-a1:no-mistakes" "brief-directpr-a2:direct-PR" "brief-localonly-a3:local-only"; do
    id=${id_mode%%:*}
    mode=${id_mode##*:}
    XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$id" some-proj --mode "$mode" >/dev/null 2>&1; status=$?
    expect_code 0 "$status" "xo-brief.sh $id --mode $mode should exit 0"
    brief="$home/data/$id/brief.md"
    assert_present "$brief" "$id: brief was not scaffolded"
    assert_grep "# Definition of done" "$brief" "$id: brief missing Definition of done section"
    grep -qx "Delivery contract: mode=$mode" "$brief" \
      || fail "$id: brief did not record its machine-readable delivery contract line"
    assert_grep "{TASK}" "$brief" "$id: brief missing the {TASK} placeholder"
    assert_grep "{XO_SPEC}" "$brief" "$id: brief missing the {XO_SPEC} placeholder"
    assert_grep "## Captain's intent" "$brief" "$id: brief missing Captain's intent subsection"
    assert_grep "## XO spec" "$brief" "$id: brief missing XO spec subsection"
    assert_grep 'never a bare number such as "PR 108"' "$brief" "$id: brief missing the full-PR-URL rule"
    assert_grep "mid-task \`working:\` line (including setup complete) is nonterminal" "$brief" \
      "$id: brief missing nonterminal working:/setup-complete gate protection"
    assert_no_grep "EOF" "$brief" "$id: brief leaked a heredoc EOF marker (unterminated heredoc)"
  done
  pass "xo-brief.sh: no-mistakes/direct-PR/local-only briefs generate cleanly"
}

# A ship task's delivery mode is xo's per-task decision, so a missing or
# unusable value must stop the scaffold instead of silently defaulting. The
# no-mistakes-prod-only row is the conditional registry policy: it is never a task
# mode, and its refusal must say to classify the task's surface first.
test_ship_mode_is_required_and_closed_set() {
  local home id out status label flag expect
  home="$TMP_ROOT/mode-required-home"
  mkdir -p "$home/data"
  id=0
  while IFS='|' read -r label flag expect; do
    [ -n "$label" ] || continue
    id=$((id + 1))
    # shellcheck disable=SC2086  # flag is an intentional word-split arg list (may be empty)
    out=$(XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "brief-required-$id" some-proj $flag 2>&1)
    status=$?
    [ "$status" -ne 0 ] || fail "$label: expected a non-zero exit"
    assert_contains "$out" "$expect" "$label: refusal did not explain the contract"
    assert_absent "$home/data/brief-required-$id/brief.md" "$label: refused scaffold still wrote a brief"
  done <<'ROWS'
missing --mode||ship briefs require --mode
empty --mode value|--mode|requires a value
unknown mode value|--mode nope|must be one of no-mistakes, direct-PR, local-only
conditional policy is not a task mode|--mode no-mistakes-prod-only|classify this task's surface
ROWS
  pass "xo-brief.sh: ship --mode is required and closed-set validated"
}

# The registry is the captain's standing posture, not this task's answer: the
# scaffold must follow the explicit flag even when the project is registered
# with a different mode, and must not consult the registry at all.
test_ship_mode_is_explicit_not_registry() {
  local home brief
  home="$TMP_ROOT/explicit-over-registry-home"
  write_registry "$home"
  XO_HOME="$home" "$ROOT/bin/xo-brief.sh" brief-explicit-a5 direct-proj --mode no-mistakes >/dev/null 2>&1 \
    || fail "explicit no-mistakes brief on a direct-PR project should scaffold"
  brief="$home/data/brief-explicit-a5/brief.md"
  grep -qx "Delivery contract: mode=no-mistakes" "$brief" \
    || fail "registered direct-PR posture overrode the explicit --mode"
  assert_grep "start /no-mistakes in that same turn to validate and ship the PR" "$brief" \
    "explicit no-mistakes brief did not render the pipeline definition of done"

  # An unregistered project is not a blocker either, because nothing is looked up.
  XO_HOME="$home" "$ROOT/bin/xo-brief.sh" brief-explicit-a6 never-registered --mode local-only >/dev/null 2>&1 \
    || fail "unregistered project should still scaffold from the explicit mode"
  grep -qx "Delivery contract: mode=local-only" "$home/data/brief-explicit-a6/brief.md" \
    || fail "unregistered project did not honour the explicit --mode"
  pass "xo-brief.sh: the explicit ship mode wins over the registered posture"
}

# yolo is xo's merge authority and never reaches the worker, and a scout
# or charter carries no delivery contract. Each must refuse rather than accept and
# discard the flag, which would look recorded but change nothing.
test_delivery_flags_are_refused_where_they_do_not_apply() {
  local home out status label args expect
  home="$TMP_ROOT/refused-flags-home"
  mkdir -p "$home/data"
  while IFS='|' read -r label args expect; do
    [ -n "$label" ] || continue
    # shellcheck disable=SC2086  # args is an intentional word-split arg list
    out=$(XO_HOME="$home" "$ROOT/bin/xo-brief.sh" $args 2>&1)
    status=$?
    [ "$status" -ne 0 ] || fail "$label: expected a non-zero exit"
    assert_contains "$out" "$expect" "$label: refusal did not explain why"
  done <<'ROWS'
yolo on a ship brief|brief-refused-b1 some-proj --mode direct-PR --yolo on|--yolo is not a brief input
yolo=value form on a ship brief|brief-refused-b2 some-proj --mode direct-PR --yolo=off|--yolo is not a brief input
mode on a scout brief|brief-refused-b3 some-proj --scout --mode direct-PR|--mode applies only to ship briefs
mode on a secondmate charter|brief-refused-b4 --secondmate --no-projects --mode no-mistakes|--mode applies only to ship briefs
ROWS
  pass "xo-brief.sh: --yolo and scout/secondmate --mode are refused, never silently dropped"
}

test_faster_paths_use_configured_authority_without_stacked_review() {
  local home id brief
  home="$TMP_ROOT/configured-authority-home"
  write_registry "$home"
  id="brief-direct-authority-a4"
  XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$id" direct-proj --mode direct-PR >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_grep "The configured merge authority decides whether to merge the PR; xo relays the outcome." "$brief" \
    "direct-PR brief lost configured merge authority"
  assert_no_grep "The captain reviews and merges the PR" "$brief" \
    "direct-PR brief hard-coded captain-only authority"
  id="brief-local-authority-a4"
  XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$id" local-proj --mode local-only >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_grep "The configured merge authority approves the ready branch, then xo merges it into local \`main\` through the guarded fast-forward path." "$brief" \
    "local-only brief lost configured merge authority and guarded landing"
  assert_no_grep "The captain approves the ready branch" "$brief" \
    "local-only brief hard-coded captain-only authority"
  assert_no_grep "XO then reviews your branch diff" "$brief" \
    "local-only brief retained a personal review stacked on the selected delivery path"
  assert_no_grep "pass \`--intent\` as only this brief's \`## Captain's intent\`" "$home/data/$id/brief.md" \
    "local-only brief must not include the no-mistakes --intent contract"
  id="brief-direct-intent-a4"
  XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$id" direct-proj --mode direct-PR >/dev/null 2>&1
  assert_no_grep "pass \`--intent\` as only this brief's \`## Captain's intent\`" "$home/data/$id/brief.md" \
    "direct-PR brief must not include the no-mistakes --intent contract"
  pass "xo-brief.sh: faster paths use configured authority without stacked review"
}

# Pin the specific line the bug lived on: the no-mistakes DOD's no-mistakes
# reference must render as plain prose with no dangling apostrophe artifact.
test_no_mistakes_dod_wording() {
  local home id brief
  home="$TMP_ROOT/wording-home"
  mkdir -p "$home/data"
  id="brief-wording-b1"
  XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$id" some-proj --mode no-mistakes >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_present "$brief" "brief was not scaffolded"
  assert_grep "no-mistakes itself provides for the mechanics" "$brief" \
    "no-mistakes DOD lost its guidance-reference sentence"
  # shellcheck disable=SC2016  # single quotes are deliberate: the backticks must stay literal
  assert_grep '`no-mistakes axi run --help`' "$brief" \
    "no-mistakes DOD must render literal backticks around the help command"
  # shellcheck disable=SC2016  # single quotes are deliberate: the backticks must stay literal
  assert_grep '`help`' "$brief" \
    "no-mistakes DOD must render literal backticks around help"
  assert_grep "pass \`--intent\` as only this brief's \`## Captain's intent\`" "$brief" \
    "no-mistakes DOD must require --intent to be the Captain's intent subsection"
  assert_grep "plus any later words the captain actually said" "$brief" \
    "no-mistakes DOD must allow later captain words in --intent"
  assert_grep "Do not include \`## XO spec\`" "$brief" \
    "no-mistakes DOD must keep XO spec out of --intent"
  assert_grep "or your own decisions and tradeoffs" "$brief" \
    "no-mistakes DOD must keep worker tradeoffs out of --intent"
  assert_grep "This replaces the no-mistakes skill's advice to enrich \`--intent\`" "$brief" \
    "no-mistakes DOD must override the external skill's enrich-with-decisions guidance"
  # A bare reference cannot preserve the captain's ask, so the rendered DOD states
  # the self-sufficiency rule and requires referenced material to be resolved into
  # its substance.
  assert_grep "The \`--intent\` string you pass must be self-sufficient" "$brief" \
    "no-mistakes DOD must require a self-sufficient --intent string"
  assert_grep "write the substance of the referenced items into \`--intent\`" "$brief" \
    "no-mistakes DOD must tell the worker to resolve report, decision, and PR references into substance"

  # The --yes ban is a fleet-wide prohibition, not a preference, and it must not
  # claim an enforcement the tool does not provide: this is instruction only.
  assert_grep "NEVER pass \`--yes\` (or \`-y\`) to \`no-mistakes axi run\` or \`no-mistakes axi respond\`. It is banned fleet-wide." "$brief" \
    "no-mistakes DOD must state the --yes ban as a prohibition"
  assert_grep "answering your own ask-user finding is a hard rule violation" "$brief" \
    "no-mistakes DOD must say why --yes is banned"
  assert_no_grep "Avoid \`--yes\`" "$brief" \
    "no-mistakes DOD still states the --yes ban as a preference"
  assert_no_grep "no-mistakes refuses" "$brief" \
    "no-mistakes DOD must not claim the tool itself refuses --yes"
  pass "xo-brief.sh: no-mistakes DOD keeps its apostrophe prose and bans --yes outright"
}

test_ask_user_escalation_format() {
  local home id brief mode other_id other_brief
  home="$TMP_ROOT/ask-user-home"
  mkdir -p "$home/data"
  id="brief-ask-user-d1"
  XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$id" some-proj --mode no-mistakes >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_present "$brief" "brief was not scaffolded"

  # A no-mistakes ask-user gate must escalate its ask-user findings as one status
  # event plus one verbatim findings snapshot file, using that same shape even
  # for a single finding, never paraphrased into the status line.
  assert_grep "escalate all ask-user findings as one event plus one snapshot file" "$brief" \
    "ship rule 6 lost the one-event-plus-snapshot-file ask-user contract"
  assert_grep "using that same shape even when the gate holds only a single ask-user finding" "$brief" \
    "ship rule 6 must require the same shape for a single finding"
  assert_grep "write only the ask-user findings, verbatim and unparaphrased (id, severity, file, line, description, authority)" "$brief" \
    "ship rule 6 must limit the verbatim axi slice to ask-user findings"
  # shellcheck disable=SC2016  # single quotes are deliberate: backticks and the key/findings/file tokens must stay literal
  assert_grep 'needs-decision [key=nm-<run>-<step>]: ask-user findings=<id1>,<id2>,... file='"$home/data/$id/nm-<run>-findings.txt" "$brief" \
    "ship rule 6 must render the exact needs-decision ask-user status line"
  assert_grep "$home/data/$id/nm-<run>-findings.txt" "$brief" \
    "ship rule 6 must point the snapshot file under this task's own data directory"
  assert_grep "The status line only points at the file; it never restates or summarizes a finding's content." "$brief" \
    "ship rule 6 must forbid paraphrasing ask-user findings into the status line"

  # The DOD's own ask-user paragraph must point back at rule 6's format
  # (one-owner rule) rather than restating or bare-citing it.
  assert_grep "escalate to xo using rule 6's ask-user format" "$brief" \
    "no-mistakes DOD ask-user paragraph must point at rule 6's format instead of a bare citation"
  assert_no_grep "escalate to xo (rule 6) and stop." "$brief" \
    "no-mistakes DOD ask-user paragraph still uses the old bare rule-6 pointer"

  other_id="brief-no-ask-user-scout"
  XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$other_id" some-proj --scout >/dev/null 2>&1
  other_brief="$home/data/$other_id/brief.md"
  assert_no_grep "destructive actions, ask-user findings" "$other_brief" \
    "scout brief received a no-mistakes-only decision case"

  for mode in direct-PR local-only; do
    other_id="brief-no-ask-user-$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')"
    XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$other_id" some-proj --mode "$mode" >/dev/null 2>&1
    other_brief="$home/data/$other_id/brief.md"
    assert_no_grep "nm-<run>-findings.txt" "$other_brief" \
      "$mode brief received a no-mistakes-only escalation format"
    assert_no_grep "destructive actions, ask-user findings" "$other_brief" \
      "$mode brief received a no-mistakes-only decision case"
  done

  pass "xo-brief.sh: no-mistakes ask-user findings use one event plus a verbatim snapshot"
}

test_ship_project_memory_wording() {
  local home id brief
  home="$TMP_ROOT/project-memory-home"
  mkdir -p "$home/data"
  id="brief-memory-c1"
  XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$id" some-proj --mode no-mistakes >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_present "$brief" "brief was not scaffolded"
  assert_grep "Record only project knowledge useful to almost every future session." "$brief" \
    "project-memory contract lost the durable-knowledge bar"
  assert_grep "prefer a pointer to the authoritative file, command, or doc over copying the detail" "$brief" \
    "project-memory contract lost pointer-over-copy guidance"
  assert_grep "follow \`$ROOT/bin/xo-ensure-agents-md.sh\`'s self-governance contract" "$brief" \
    "project-memory contract no longer defers to the ensure helper"
  pass "xo-brief.sh: ship project-memory wording carries the AGENTS.md authoring bar"
}

test_herdr_lab_contract_is_explicit_and_complete() {
  local home id brief
  home="$TMP_ROOT/herdr-lab-home"
  mkdir -p "$home/data"
  id="brief-herdr-lab-d1"
  XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$id" xo --mode no-mistakes --herdr-lab >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_present "$brief" "Herdr lab brief was not scaffolded"
  assert_grep "# Herdr isolation - HARD SAFETY CONTRACT" "$brief" \
    "Herdr lab brief missing its hard safety contract"
  assert_grep "HERDR_LAB_HELPER='$ROOT/bin/xo-herdr-lab.sh'" "$brief" \
    "Herdr lab brief must bind the absolute XO helper path"
  assert_grep "HERDR_LAB_SESSION=\$(\"\$HERDR_LAB_HELPER\" name $id)" "$brief" \
    "Herdr lab brief missing helper-owned session naming"
  assert_grep "\"\$HERDR_LAB_HELPER\" provision \"\$HERDR_LAB_SESSION\"" "$brief" \
    "Herdr lab brief missing helper-owned provisioning"
  assert_grep "\"\$HERDR_LAB_HELPER\" teardown \"\$HERDR_LAB_SESSION\"" "$brief" \
    "Herdr lab brief missing helper-owned teardown"
  assert_grep "required trailing \`--session \"\$HERDR_LAB_SESSION\"\`" "$brief" \
    "Herdr lab brief missing the per-call trailing session contract"
  assert_grep "direct \`herdr server stop\`" "$brief" \
    "Herdr lab brief missing the forbidden server-global command list"
  assert_grep "records the live default session before provisioning" "$brief" \
    "Herdr lab brief missing the before tripwire"
  assert_grep "verifies the identical fleet state after teardown" "$brief" \
    "Herdr lab brief missing the after tripwire"
  assert_no_grep "Herdr lifecycle declaration - NOT ENABLED" "$brief" \
    "Herdr lab brief retained the unguarded declaration"
  pass "xo-brief.sh: --herdr-lab emits the complete hard safety contract"
}

test_herdr_lab_contract_quotes_foreign_xo_path() {
  local home id brief foreign_root helper
  home="$TMP_ROOT/herdr-lab-foreign-home"
  foreign_root="$TMP_ROOT/xo helper's root"
  mkdir -p "$home/data"
  id="brief-herdr-lab-foreign-d2"
  helper=$(printf '%s' "$foreign_root/bin/xo-herdr-lab.sh" | sed "s/'/'\\\\''/g")
  helper="'$helper'"
  XO_HOME="$home" XO_ROOT_OVERRIDE="$foreign_root" "$ROOT/bin/xo-brief.sh" "$id" foreign --scout --herdr-lab >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_grep "HERDR_LAB_HELPER=$helper" "$brief" \
    "Herdr lab brief must shell-quote an absolute XO helper path"
  assert_no_grep "bin/xo-herdr-lab.sh name $id" "$brief" \
    "Herdr lab brief must not invoke a worktree-relative helper"
  pass "xo-brief.sh: --herdr-lab uses its quoted XO-owned helper path"
}

test_herdr_lab_omission_is_loud_for_ship_and_scout() {
  local home id brief
  home="$TMP_ROOT/herdr-gate-home"
  mkdir -p "$home/data"
  for kind in ship scout; do
    id="brief-herdr-gate-$kind"
    if [ "$kind" = scout ]; then
      XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$id" xo --scout >/dev/null 2>&1
    else
      XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$id" xo --mode no-mistakes >/dev/null 2>&1
    fi
    brief="$home/data/$id/brief.md"
    assert_grep "# Herdr lifecycle declaration - NOT ENABLED" "$brief" \
      "$kind brief silently omitted the Herdr declaration"
    assert_grep "regenerate the brief with \`--herdr-lab\` before dispatch" "$brief" \
      "$kind brief missing the fail-visible regeneration instruction"
  done
  pass "xo-brief.sh: ship and scout scaffolds make omitted Herdr intent fail-visible"
}

# Regression (issue #2575): AGENTS.md section 11 and this script's own help tell
# xo to fill `{TASK}` and `{XO_SPEC}`. The unguarded Herdr gate used
# to quote `{TASK}` in its own prose, so that documented global replace spliced
# the whole task body into the middle of the gate's sentence - silently
# destroying the one contract that exists precisely because the scaffold cannot
# see the task text. Each placeholder must exist only at its genuine fill site,
# so the documented fill leaves the gate intact and each body appears once.
test_documented_global_replace_leaves_the_herdr_gate_intact() {
  local home id brief kind count content filled body spec
  home="$TMP_ROOT/task-fill-site-home"
  mkdir -p "$home/data"
  body='Restart the herdr session, then profile it'
  spec='Use the isolated lab helper for every lifecycle call'
  for kind in ship scout; do
    id="brief-fill-site-$kind"
    if [ "$kind" = scout ]; then
      XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$id" xo --scout >/dev/null 2>&1
    else
      XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$id" xo --mode no-mistakes >/dev/null 2>&1
    fi
    brief="$home/data/$id/brief.md"
    assert_present "$brief" "$kind brief was not scaffolded"
    count=$(grep -c -F '{TASK}' "$brief")
    [ "$count" = 1 ] \
      || fail "$kind brief must carry exactly one {TASK} fill site, found $count"
    count=$(grep -c -F '{XO_SPEC}' "$brief")
    [ "$count" = 1 ] \
      || fail "$kind brief must carry exactly one {XO_SPEC} fill site, found $count"
    content=$(cat "$brief")
    filled=${content//'{TASK}'/$body}
    filled=${filled//'{XO_SPEC}'/$spec}
    count=$(printf '%s\n' "$filled" | grep -c -F "$body")
    [ "$count" = 1 ] \
      || fail "$kind brief: the documented {TASK} replace duplicated the intent body $count times"
    count=$(printf '%s\n' "$filled" | grep -c -F "$spec")
    [ "$count" = 1 ] \
      || fail "$kind brief: the {XO_SPEC} replace duplicated the spec body $count times"
    printf '%s\n' "$filled" | grep -qF 'this scaffold cannot inspect the task text' \
      || fail "$kind brief: the Herdr safety gate did not survive the documented fill"
  done
  pass "xo-brief.sh: the documented {TASK} and {XO_SPEC} fills cannot corrupt the Herdr safety gate"
}

test_secondmate_no_projects_charter() {
  local home brief status
  home="$TMP_ROOT/no-projects-home"
  mkdir -p "$home/data"

  # The deliberate --no-projects signal scaffolds a valid project-less charter for
  # a domain whose subject is the xo repo itself (no clones needed).
  XO_HOME="$home" XO_SECONDMATE_CHARTER='xo self-development' \
    XO_SECONDMATE_SCOPE='xo repo work' \
    "$ROOT/bin/xo-brief.sh" fdev --secondmate --no-projects >/dev/null 2>&1; status=$?
  expect_code 0 "$status" "--no-projects secondmate brief should exit 0"
  brief="$home/data/fdev/brief.md"
  assert_present "$brief" "project-less charter was not scaffolded"
  assert_grep "# Project clones" "$brief" "project-less charter dropped the Project clones heading"
  assert_grep "None. This is a project-less domain" "$brief" \
    "project-less charter did not render a sensible no-clones note"
  assert_grep "its crews take pooled worktrees of that repo" "$brief" \
    "project-less charter operating model lost the pooled-worktree note"
  assert_no_grep "The projects above are local clones" "$brief" \
    "project-less charter kept the with-projects operating-model line"
  assert_grep '# The captain and the parent channel' "$brief" \
    "secondmate charter lost the parent-channel section"
  assert_grep 'Nobody reads this chat' "$brief" \
    "secondmate charter no longer says the chat is unread"
  assert_grep 'in this home it IS the captain' "$brief" \
    "secondmate charter no longer names the parent channel as the captain"
  assert_grep 'working [key=<work-slug>]' "$brief" \
    "secondmate charter did not key material routed-work phases"
  assert_grep 'resolved [key=<work-slug>]' "$brief" \
    "secondmate charter did not close a quietly ended routed-work phase"
  assert_grep 'use the same key on its later' "$brief" \
    "secondmate charter did not supersede working phases with later states"
  if grep -nE '^-[[:space:]]*$' "$brief" >/dev/null; then
    fail "project-less charter left a stray empty project bullet"
  fi

  # Accidental omission (no projects, no signal) still fails loudly, writing nothing.
  XO_HOME="$home" XO_SECONDMATE_CHARTER='x' "$ROOT/bin/xo-brief.sh" oops --secondmate >/dev/null 2>&1; status=$?
  expect_code 1 "$status" "secondmate brief with no projects and no --no-projects must fail"
  assert_absent "$home/data/oops/brief.md" "loud-failure secondmate brief still wrote a file"

  # --no-projects is mutually exclusive with a project list.
  XO_HOME="$home" XO_SECONDMATE_CHARTER='x' "$ROOT/bin/xo-brief.sh" oops2 --secondmate --no-projects alpha >/dev/null 2>&1; status=$?
  expect_code 1 "$status" "--no-projects combined with a project list must fail"

  # --no-projects applies only to secondmate charters, never a ship/scout brief.
  XO_HOME="$home" "$ROOT/bin/xo-brief.sh" oops3 somerepo --no-projects >/dev/null 2>&1; status=$?
  expect_code 1 "$status" "--no-projects on a ship brief must fail"

  pass "xo-brief.sh: --no-projects scaffolds a project-less charter and guards misuse"
}

test_secondmate_marked_request_reporting_contract() {
  local home brief
  home="$TMP_ROOT/marked-request-reporting-home"
  mkdir -p "$home/data"
  XO_HOME="$home" XO_CLASSIFY_PAUSED_VERB=paused \
    XO_SECONDMATE_CHARTER='Handle routed domain work.' \
    "$ROOT/bin/xo-brief.sh" marked-request-reporting --secondmate --no-projects >/dev/null 2>&1
  brief="$home/data/marked-request-reporting/brief.md"

  assert_grep 'A marked request requires one correlated answer after the work' "$brief" \
    "secondmate charter did not require the correlated answer after the work"
  assert_grep 'does not require a separate receipt or start acknowledgement' "$brief" \
    "secondmate charter did not reject a separate receipt/start acknowledgement"
  assert_grep "Never append \`working:\` merely to acknowledge receipt or announce that a marked request has started." "$brief" \
    "secondmate charter did not forbid a generic working acknowledgement"
  assert_no_grep "Give every routed-work phase a stable key: open it with \`working" "$brief" \
    "secondmate charter retained the unconditional working opener"
  assert_grep 'When a routed-work phase has a supervisor-actionable material change worth reporting under the rule above' "$brief" \
    "secondmate charter did not limit keyed phases to reportable material changes"
  assert_grep "If its first reportable event is \`working [key=<work-slug>]: {material phase}\`" "$brief" \
    "secondmate charter lost keyed working syntax for a reportable material phase"
  assert_grep "use the same key on its later \`paused\`, \`done\`, \`failed\`, \`needs-decision\`, or \`blocked\` event" "$brief" \
    "secondmate charter lost same-key closure for a reportable material phase"
  assert_grep 'resolved [key=<work-slug>]' "$brief" \
    "secondmate charter lost resolved closure for a keyed material phase"

  assert_grep 'include that exact token in your parent status reply' "$brief" \
    "secondmate charter lost correlated parent results"
  assert_grep 'bin/xo-secondmate-report.sh <verb> <corr_id> <note>' "$brief" \
    "secondmate charter lost the mechanical helper invocation"
  assert_grep 'do not pass a status path' "$brief" \
    "secondmate charter still tells the mate to pass a hand path to the helper"
  assert_grep 'For a terse result, a status line is the whole answer.' "$brief" \
    "secondmate charter lost terse result reporting"
  assert_grep 'append a status line that points to that doc' "$brief" \
    "secondmate charter lost detailed document pointers"
  assert_grep 'Report only true captain-relevant outcomes or a declared external wait' "$brief" \
    "secondmate charter lost declared external waits"
  assert_grep 'a captain decision, a real blocker, a failure, work ready for review, or work you landed' "$brief" \
    "secondmate charter lost decisions, blockers, failures, ready outcomes, or landed work"
  # Under standing merge authority nothing is ever "ready for review", so the
  # landed merge is the trigger a charter without this line silently omits.
  assert_grep 'a merge you performed yourself under standing merge authority and one the captain merged on the forge' "$brief" \
    "secondmate charter did not name a landed merge as a reporting trigger"
  assert_grep 'States: working, needs-decision, blocked, paused, done, failed.' "$brief" \
    "secondmate charter changed the preserved status vocabulary"
  pass "xo-brief.sh: marked requests avoid generic acknowledgements and preserve material reporting"
}

test_secondmate_directory_paths_are_absolute_and_output_is_stable() {
  local root home data_override state_override brief baseline err status
  root="$TMP_ROOT/relative-directory-inputs"
  mkdir -p "$root"
  root=$(cd "$root" && pwd -P)
  home="$root/home"
  data_override="$root/data-override"
  state_override="$root/state-override"
  mkdir -p "$home/data" "$home/state" "$data_override" "$state_override" \
    "$root/cdpath/home/data" "$root/cdpath/home/state" \
    "$root/cdpath/data-override" "$root/cdpath/state-override"

  brief="$home/data/relative-home/brief.md"
  XO_HOME="$home" XO_SECONDMATE_CHARTER=x \
    "$ROOT/bin/xo-brief.sh" relative-home --secondmate --no-projects >/dev/null 2>&1
  baseline="$root/absolute-home-charter"
  cp "$brief" "$baseline"
  rm -f "$brief"
  (
    cd "$root" || exit 1
    CDPATH="$root/cdpath" XO_HOME=home XO_SECONDMATE_CHARTER=x \
      "$ROOT/bin/xo-brief.sh" relative-home --secondmate --no-projects >/dev/null 2>&1
  )
  cmp -s "$baseline" "$brief" \
    || fail "relative XO_HOME changed charter bytes compared with the same absolute home"
  assert_grep ">> '$home/state/relative-home.status'" "$brief" \
    "relative XO_HOME did not render an absolute secondmate status path"

  brief="$home/data/relative-state/brief.md"
  XO_HOME="$home" XO_STATE_OVERRIDE="$state_override" XO_SECONDMATE_CHARTER=x \
    "$ROOT/bin/xo-brief.sh" relative-state --secondmate --no-projects >/dev/null 2>&1
  baseline="$root/absolute-state-charter"
  cp "$brief" "$baseline"
  rm -f "$brief"
  (
    cd "$root" || exit 1
    CDPATH="$root/cdpath" XO_HOME="$home" XO_STATE_OVERRIDE=state-override XO_SECONDMATE_CHARTER=x \
      "$ROOT/bin/xo-brief.sh" relative-state --secondmate --no-projects >/dev/null 2>&1
  )
  cmp -s "$baseline" "$brief" \
    || fail "relative XO_STATE_OVERRIDE changed charter bytes compared with the same absolute state directory"
  assert_grep ">> '$state_override/relative-state.status'" "$brief" \
    "relative XO_STATE_OVERRIDE did not render an absolute secondmate status path"

  brief="$data_override/relative-data/brief.md"
  XO_HOME="$home" XO_DATA_OVERRIDE="$data_override" XO_SECONDMATE_CHARTER=x \
    "$ROOT/bin/xo-brief.sh" relative-data --secondmate --no-projects >/dev/null 2>&1
  baseline="$root/absolute-data-charter"
  cp "$brief" "$baseline"
  rm -f "$brief"
  (
    cd "$root" || exit 1
    CDPATH="$root/cdpath" XO_HOME="$home" XO_DATA_OVERRIDE=data-override XO_SECONDMATE_CHARTER=x \
      "$ROOT/bin/xo-brief.sh" relative-data --secondmate --no-projects >/dev/null 2>&1
  )
  cmp -s "$baseline" "$brief" \
    || fail "relative XO_DATA_OVERRIDE changed charter bytes compared with the same absolute data directory"
  assert_grep ">> '$home/state/relative-data.status'" "$brief" \
    "relative XO_DATA_OVERRIDE changed the absolute default status path"

  err="$root/unresolved.err"
  (
    cd "$root" || exit 1
    XO_HOME=missing-home XO_SECONDMATE_CHARTER=x \
      "$ROOT/bin/xo-brief.sh" unresolved-home --secondmate --no-projects >/dev/null 2>"$err"
  ); status=$?
  expect_code 1 "$status" "an unresolved relative XO_HOME must fail"
  assert_grep "XO_HOME directory cannot be resolved: missing-home" "$err" \
    "unresolved relative XO_HOME did not fail loudly"

  (
    cd "$root" || exit 1
    XO_HOME="$home" XO_STATE_OVERRIDE=missing-state XO_SECONDMATE_CHARTER=x \
      "$ROOT/bin/xo-brief.sh" unresolved-state --secondmate --no-projects >/dev/null 2>"$err"
  ); status=$?
  expect_code 1 "$status" "an unresolved relative XO_STATE_OVERRIDE must fail"
  assert_grep "XO_STATE_OVERRIDE directory cannot be resolved: missing-state" "$err" \
    "unresolved relative XO_STATE_OVERRIDE did not fail loudly"

  (
    cd "$root" || exit 1
    XO_HOME="$home" XO_DATA_OVERRIDE=missing-data XO_SECONDMATE_CHARTER=x \
      "$ROOT/bin/xo-brief.sh" unresolved-data --secondmate --no-projects >/dev/null 2>"$err"
  ); status=$?
  expect_code 1 "$status" "an unresolved relative XO_DATA_OVERRIDE must fail"
  assert_grep "XO_DATA_OVERRIDE directory cannot be resolved: missing-data" "$err" \
    "unresolved relative XO_DATA_OVERRIDE did not fail loudly"

  pass "xo-brief.sh: relative directory inputs ignore CDPATH, render stable absolute charter paths, or fail loudly"
}

test_herdr_lab_contract_applies_to_scouts_but_not_secondmates() {
  local home brief status=0
  home="$TMP_ROOT/herdr-kind-home"
  mkdir -p "$home/data"
  XO_HOME="$home" "$ROOT/bin/xo-brief.sh" herdr-scout xo --scout --herdr-lab >/dev/null 2>&1
  brief="$home/data/herdr-scout/brief.md"
  assert_grep "# Herdr isolation - HARD SAFETY CONTRACT" "$brief" \
    "scout --herdr-lab brief missing the contract"

  XO_HOME="$home" XO_SECONDMATE_CHARTER=ops "$ROOT/bin/xo-brief.sh" herdr-secondmate --secondmate xo --herdr-lab >/dev/null 2>&1 || status=$?
  expect_code 1 "$status" "secondmate --herdr-lab must be rejected"
  assert_absent "$home/data/herdr-secondmate/brief.md" \
    "rejected secondmate --herdr-lab still wrote a brief"
  pass "xo-brief.sh: Herdr lab contract covers scouts and rejects secondmate misuse"
}

test_pause_verb_override_renders_all_brief_scaffolds() {
  local home kind id brief
  home="$TMP_ROOT/pause-verb-home"
  mkdir -p "$home/data"

  for kind in ship scout secondmate; do
    id="brief-pause-verb-$kind"
    case "$kind" in
      ship)
        XO_HOME="$home" XO_CLASSIFY_PAUSED_VERB=awaiting \
          "$ROOT/bin/xo-brief.sh" "$id" xo --mode no-mistakes >/dev/null 2>&1
        ;;
      scout)
        XO_HOME="$home" XO_CLASSIFY_PAUSED_VERB=awaiting \
          "$ROOT/bin/xo-brief.sh" "$id" xo --scout >/dev/null 2>&1
        ;;
      secondmate)
        XO_HOME="$home" XO_CLASSIFY_PAUSED_VERB=awaiting \
          "$ROOT/bin/xo-brief.sh" "$id" --secondmate --no-projects >/dev/null 2>&1
        ;;
    esac
    brief="$home/data/$id/brief.md"
    assert_grep "States: working, needs-decision, blocked, awaiting, done, failed." "$brief" \
      "$kind brief did not render the configured pause verb in its states list"
    # shellcheck disable=SC2016 # Literal backticks and braces must remain unexpanded.
    assert_grep 'Use `awaiting: {why}`' "$brief" \
      "$kind brief did not instruct the configured pause status"
    # shellcheck disable=SC2016 # Literal backticks and braces must remain unexpanded.
    assert_no_grep '`paused: {why}`' "$brief" \
      "$kind brief still instructs the default paused status"
    assert_grep 'a blocker or wait clears' "$brief" \
      "$kind brief did not require durable resolution when a blocker clears"
    assert_grep 'even when the answer is what started that work' "$brief" \
      "$kind brief did not warn that an answer-started done/working never closes a decision"
  done
  pass "xo-brief.sh: custom pause verb renders in every scaffold"
}

test_scout_and_secondmate_load_decision_hold_policy() {
  local home scout charter
  home="$TMP_ROOT/decision-policy-home"
  mkdir -p "$home/data"
  XO_HOME="$home" XO_ROOT_OVERRIDE="$ROOT" \
    "$ROOT/bin/xo-brief.sh" sample-investigation sample --scout >/dev/null 2>&1
  scout="$home/data/sample-investigation/brief.md"
  assert_grep "$ROOT/.agents/skills/captain-hold-lifecycle/SKILL.md" "$scout" \
    "scout brief did not load the captain-call policy before done"
  assert_grep "pass its shared completion gate for the report and any visual review" "$scout" \
    "scout brief did not cross-reference visual-review completion"
  XO_HOME="$home" XO_ROOT_OVERRIDE="$ROOT" XO_SECONDMATE_CHARTER='sample reviews' \
    "$ROOT/bin/xo-brief.sh" sample-mate --secondmate --no-projects >/dev/null 2>&1
  charter="$home/data/sample-mate/brief.md"
  assert_grep "load \`captain-hold-lifecycle\`" "$charter" \
    "secondmate charter did not load the shared captain-call policy for detailed investigations"
  pass "xo-brief.sh: investigation and visual-review completions load the shared decision policy"
}

# A scout brief offers the Lavish review loop only when bootstrap confirms the
# supported lavish-axi floor at scaffold time; a missing or older build gets a
# text-report instruction instead, so a scout never drives a below-floor Lavish.
test_scout_lavish_line_follows_presentation_floor() {
  local base label version expect case_dir fakebin brief n=0
  local hosting='you may host the Lavish review loop yourself'
  local text_only='deliver your findings as a text report without Lavish'
  base=$(xo_test_base_path_sans "${XO_TEST_BASE_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}" lavish-axi)
  while IFS='^' read -r label version expect; do
    [ -n "$label" ] || continue
    n=$((n + 1))
    case_dir="$TMP_ROOT/scout-lavish-$n"
    mkdir -p "$case_dir/home/data"
    fakebin=$(xo_fakebin "$case_dir")
    [ "$version" = absent ] || xo_fake_version_tool "$fakebin" lavish-axi XO_FAKE_LAVISH_AXI_VERSION "$version"
    PATH="$fakebin:$base" XO_HOME="$case_dir/home" \
      "$ROOT/bin/xo-brief.sh" scout-lavish alpha --scout >/dev/null \
      || fail "$label: scout scaffold failed"
    brief="$case_dir/home/data/scout-lavish/brief.md"
    if [ "$expect" = hosting ]; then
      assert_grep "$hosting" "$brief" "$label: scout brief did not offer the Lavish review loop"
      assert_no_grep "$text_only" "$brief" "$label: scout brief withheld Lavish from a compatible build"
    else
      assert_grep "$text_only" "$brief" "$label: scout brief did not ask for a text report"
      assert_no_grep "$hosting" "$brief" "$label: scout brief offered a below-floor Lavish"
    fi
  done <<'ROWS'
lavish-axi at the floor^0.1.46^hosting
lavish-axi above the floor^0.2.0^hosting
lavish-axi just below the floor^0.1.45^text
absent lavish-axi^absent^text
ROWS
  pass "xo-brief.sh: scout Lavish hosting follows the bootstrap lavish-axi floor"
}

# Scout and secondmate paths still scaffold well-formed briefs.
test_scout_and_secondmate_scaffold() {
  local brief
  XO_HOME="$BRIEF_HOME" "$ROOT/bin/xo-brief.sh" brief-scout-q6 alpha --scout >/dev/null 2>&1 \
    || fail "xo-brief.sh scout scaffold exited non-zero"
  brief="$BRIEF_HOME/data/brief-scout-q6/brief.md"
  assert_present "$brief" "scout brief was not scaffolded"
  assert_grep "SCOUT task" "$brief" "scout brief must declare itself a scout task"
  assert_grep "report.md" "$brief" "scout brief must point at the report deliverable"
  assert_grep "## Captain's intent" "$brief" "scout brief missing Captain's intent subsection"
  assert_grep "## XO spec" "$brief" "scout brief missing XO spec subsection"
  assert_grep "{XO_SPEC}" "$brief" "scout brief missing the spec placeholder"

  XO_SECONDMATE_CHARTER='Supervise the alpha domain.' \
    XO_HOME="$BRIEF_HOME" "$ROOT/bin/xo-brief.sh" brief-sm-q6 --secondmate alpha >/dev/null 2>&1 \
    || fail "xo-brief.sh secondmate scaffold exited non-zero"
  brief="$BRIEF_HOME/data/brief-sm-q6/brief.md"
  assert_present "$brief" "secondmate charter was not scaffolded"
  assert_grep "persistent second mate" "$brief" \
    "secondmate charter must declare its role"
  assert_no_grep "## Captain's intent" "$brief" \
    "secondmate charter must not grow ship/scout Task subsections"
  assert_no_grep "{XO_SPEC}" "$brief" \
    "secondmate charter must not carry the XO spec placeholder"
  pass "xo-brief: scout and secondmate code paths still scaffold well-formed briefs"
}

test_worker_role_scope() {
  local kind home brief
  home="$TMP_ROOT/worker-role"
  for kind in no-mistakes direct-PR local-only scout; do
    if [ "$kind" = scout ]; then
      XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$kind" arbitrary-project-name --scout >/dev/null || fail "scout scaffold failed"
    else
      XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$kind" arbitrary-project-name --mode "$kind" >/dev/null || fail "$kind scaffold failed"
    fi
    brief="$home/data/$kind/brief.md"
    assert_no_grep '# Current worker role contract' "$brief" "$kind scaffolded a second owner of the role scope xo-spawn.sh delivers"
  done
  XO_HOME="$home" XO_SECONDMATE_CHARTER='Supervise assigned work.' \
    "$ROOT/bin/xo-brief.sh" supervisor --secondmate --no-projects >/dev/null || fail "secondmate scaffold failed"
  brief="$home/data/supervisor/brief.md"
  assert_no_grep '# Current worker role contract' "$brief" "secondmate received the worker exception"
  assert_no_grep 'do not adopt the supervisor identity' "$brief" "secondmate received the worker exception"
  assert_grep "The local \`AGENTS.md\` is your job description" "$brief" "secondmate lost its supervisor contract"
  assert_grep 'That file is your parent channel' "$brief" "secondmate lost its parent channel"
  pass "xo-brief: scaffolds leave the worker role scope to the launch boundary and keep the secondmate contract"
}

# The delivery contract binds only if the worker cannot read a local commit as
# done. Three parallel no-mistakes workers reported done after a local commit on
# 2026-09-12 because the brief itself offered a done line at the commit and left
# the pipeline to a later steer. Every ship brief must now name its mode's one
# accepted done line and declare any other done line not a done, both where the
# worker reports (the status protocol, rule 4) and where it gates (the Definition
# of done); it must carry no other mode's done line; and the no-mistakes brief
# must have the worker start the pipeline itself with no done line at the commit.
test_done_line_is_bound_to_delivery_mode() {
  local home id mode brief line protocol dod part file
  # shellcheck disable=SC2016  # single quotes are deliberate: the backticks must stay literal
  local not_a_done='a `done:` line without that evidence is not a done'
  local stopped_short='xo treats it as a worker that stopped short of delivery'
  home="$TMP_ROOT/done-binding-home"
  mkdir -p "$home/data"
  for mode in no-mistakes direct-PR local-only; do
    id="brief-done-binding-$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')"
    XO_HOME="$home" "$ROOT/bin/xo-brief.sh" "$id" some-proj --mode "$mode" >/dev/null 2>&1 \
      || fail "$mode: brief should scaffold"
    brief="$home/data/$id/brief.md"
    # shellcheck disable=SC2016  # single quotes are deliberate: the backticks and braces must stay literal
    case "$mode" in
      no-mistakes) line='`done: PR {url} checks green`' ;;
      direct-PR) line='`done: PR {url}`' ;;
      local-only) line="\`done: ready in branch xo/$id\`" ;;
    esac
    # The status protocol is rule 4 up to rule 5; the gate is everything from the
    # Definition of done heading on. Both must carry the same binding.
    protocol="$TMP_ROOT/done-binding-$id-protocol"
    dod="$TMP_ROOT/done-binding-$id-dod"
    awk '/^5\. / { exit } /^4\. Report status/ { emit=1 } emit' "$brief" > "$protocol"
    awk '/^# Definition of done$/ { emit=1 } emit' "$brief" > "$dod"
    [ -s "$protocol" ] || fail "$mode: brief has no status protocol rule 4 to bind"
    [ -s "$dod" ] || fail "$mode: brief has no Definition of done to bind"
    for part in protocol dod; do
      file="$TMP_ROOT/done-binding-$id-$part"
      assert_grep "the only \`done:\` line that counts is $line" "$file" \
        "$mode: the $part does not name the mode's one accepted done line"
      assert_grep "$not_a_done" "$file" \
        "$mode: the $part does not declare a done line without evidence not a done"
      assert_grep "$stopped_short" "$file" \
        "$mode: the $part does not say a bare done is treated as a worker that stopped short"
    done
    assert_no_grep 'done: {summary}' "$brief" \
      "$mode: brief still offers a free-form done line"
    assert_no_grep "XO will then instruct you to run /no-mistakes" "$brief" \
      "$mode: brief still leaves the pipeline start to a later steer"
    case "$mode" in
      no-mistakes)
        assert_grep 'A local commit with passing local checks, a started pipeline run, or an open PR still waiting on CI is not done' "$brief" \
          "no-mistakes brief does not rule out the commit-with-local-checks false done"
        assert_grep 'working: implementation committed, starting no-mistakes' "$dod" \
          "no-mistakes brief does not report the commit as a nonterminal working line"
        assert_grep 'do not wait for xo to tell you to start the pipeline' "$dod" \
          "no-mistakes brief still waits for a steer to start the pipeline"
        assert_grep "append \`done: PR {url} checks green\` and stop" "$dod" \
          "no-mistakes brief lost its CI-green done gate"
        # shellcheck disable=SC2016  # single quotes are deliberate: the backticks and braces must stay literal
        assert_no_grep '`done: PR {url}`' "$brief" \
          "no-mistakes brief carries the direct-PR done line"
        assert_no_grep 'ready in branch' "$brief" \
          "no-mistakes brief carries the local-only done line"
        ;;
      direct-PR)
        assert_grep 'A local commit or a pushed branch with no PR is not done' "$brief" \
          "direct-PR brief does not rule out the commit-without-PR false done"
        assert_no_grep 'checks green' "$brief" \
          "direct-PR brief carries the no-mistakes done line"
        assert_no_grep 'ready in branch' "$brief" \
          "direct-PR brief carries the local-only done line"
        ;;
      local-only)
        assert_grep 'Uncommitted work or a branch that no longer fast-forwards is not done' "$brief" \
          "local-only brief does not rule out the uncommitted false done"
        assert_no_grep 'done: PR' "$brief" \
          "local-only brief carries a PR done line"
        ;;
    esac
  done
  pass "xo-brief.sh: every ship brief binds done to its mode's evidence at the report site and at the gate"
}

test_worker_role_scope
test_done_line_is_bound_to_delivery_mode
test_script_parses
test_no_heredoc_in_command_substitution
test_help_includes_entire_header
test_ship_modes_generate_clean_briefs
test_ship_mode_is_required_and_closed_set
test_ship_mode_is_explicit_not_registry
test_delivery_flags_are_refused_where_they_do_not_apply
test_faster_paths_use_configured_authority_without_stacked_review
test_no_mistakes_dod_wording
test_ask_user_escalation_format
test_ship_project_memory_wording
test_herdr_lab_contract_is_explicit_and_complete
test_herdr_lab_contract_quotes_foreign_xo_path
test_herdr_lab_omission_is_loud_for_ship_and_scout
test_documented_global_replace_leaves_the_herdr_gate_intact
test_herdr_lab_contract_applies_to_scouts_but_not_secondmates
test_secondmate_no_projects_charter
test_secondmate_marked_request_reporting_contract
test_secondmate_directory_paths_are_absolute_and_output_is_stable
test_pause_verb_override_renders_all_brief_scaffolds
test_scout_and_secondmate_load_decision_hold_policy
test_scout_and_secondmate_scaffold
test_scout_lavish_line_follows_presentation_floor
