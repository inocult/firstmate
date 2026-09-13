#!/usr/bin/env bash
# Parity guard for xo's shell-lint definition.
#
# bin/xo-lint.sh must be the single owner that BOTH CI
# (.github/workflows/ci.yml) and the pre-push gate (.no-mistakes.yaml
# commands.lint) invoke, so the local lint can never diverge from CI again.
# Regression origin: with no commands.lint configured, the local no-mistakes
# lint step never ran the deterministic
# `shellcheck bin/*.sh bin/backends/*.sh tests/*.sh`, so PRs passed local
# validation yet failed that exact check in CI on info/warning findings such as
# SC2015, SC1007, and SC2034. A second axis was tool-version skew: CI's
# ShellCheck floated with the runner image and still emitted SC2015, which
# ShellCheck retired in 0.11.0. xo-lint.sh now pins one exact version and both
# gates resolve it, so command, file set, config, AND version all match.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LINT="$ROOT/bin/xo-lint.sh"
INSTALLER="$ROOT/bin/xo-install-shellcheck.sh"
# The pinned version, read from the single source (the one owner itself).
REQUIRED=$("$LINT" --required-version)

# Official GitHub release asset sha256 values for shellcheck v0.11.0 .tar.xz
# archives (https://github.com/koalaman/shellcheck/releases/tag/v0.11.0). Tests
# compare installer behavior against these published digests, not script source.
SHELLCHECK_SHA_LINUX_X86_64=8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
SHELLCHECK_SHA_LINUX_AARCH64=12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588
SHELLCHECK_SHA_DARWIN_X86_64=3c89db4edcab7cf1c27bff178882e0f6f27f7afdf54e859fa041fca10febe4c6
SHELLCHECK_SHA_DARWIN_AARCH64=56affdd8de5527894dca6dc3d7e0a99a873b0f004d7aabc30ae407d3f48b0a79

# xo_install_stub_uname <fakebin>: uname -s / uname -m from XO_TEST_UNAME_S/M.
xo_install_stub_uname() {
  local fakebin=$1
  cat > "$fakebin/uname" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf '%s\n' "${XO_TEST_UNAME_S:-Linux}" ;;
  -m) printf '%s\n' "${XO_TEST_UNAME_M:-x86_64}" ;;
  *) printf '%s\n' "${XO_TEST_UNAME_S:-Linux}" ;;
esac
SH
  chmod +x "$fakebin/uname"
}

# xo_install_stub_curl <fakebin>: log the URL, fail CURL_FAIL_UNTIL times, then
# write an empty file at -o. CURL_COUNT and CURL_URL_LOG are paths the stub
# updates when invoked.
xo_install_stub_curl() {
  local fakebin=$1
  cat > "$fakebin/curl" <<'SH'
#!/usr/bin/env bash
count=0
[ ! -f "${CURL_COUNT:-}" ] || count=$(cat "$CURL_COUNT")
count=$((count + 1))
[ -z "${CURL_COUNT:-}" ] || printf '%s\n' "$count" > "$CURL_COUNT"
url=
out=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out=$2
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url=$1
      shift
      ;;
  esac
done
[ -z "${CURL_URL_LOG:-}" ] || printf '%s\n' "$url" >> "$CURL_URL_LOG"
fail_until=${CURL_FAIL_UNTIL:-0}
[ "$count" -gt "$fail_until" ] || exit 22
: > "$out"
exit 0
SH
  chmod +x "$fakebin/curl"
}

# xo_install_stub_hasher <fakebin> <name>: sha256sum or shasum stub that prints
# SHA256_STUB_HASH and records the invocation on HASHER_LOG. shasum requires -a 256.
xo_install_stub_hasher() {
  local fakebin=$1 name=$2
  cat > "$fakebin/$name" <<'SH'
#!/usr/bin/env bash
self=${0##*/}
if [ -n "${HASHER_LOG:-}" ]; then
  printf '%s\n' "$self $*" >> "$HASHER_LOG"
fi
file=$1
if [ "$self" = shasum ]; then
  algo=
  file=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -a)
        algo=$2
        shift 2
        ;;
      *)
        file=$1
        shift
        ;;
    esac
  done
  [ "$algo" = 256 ] || exit 1
fi
printf '%s  %s\n' "${SHA256_STUB_HASH:?}" "$file"
SH
  chmod +x "$fakebin/$name"
}

xo_install_stub_tar_shellcheck() {
  local fakebin=$1
  cat > "$fakebin/tar" <<'SH'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-C" ]; then
    mkdir -p "$2/shellcheck-v0.11.0"
    cat > "$2/shellcheck-v0.11.0/shellcheck" <<'EOF'
#!/usr/bin/env bash
printf 'ShellCheck - shell script analysis tool\nversion: 0.11.0\n'
EOF
    chmod +x "$2/shellcheck-v0.11.0/shellcheck"
    exit 0
  fi
  shift
done
exit 2
SH
  chmod +x "$fakebin/tar"
}

xo_install_stub_sleep() {
  local fakebin=$1
  cat > "$fakebin/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fakebin/sleep"
}

# True only when the resolved shellcheck is exactly the pinned version, so the
# lint-running tests below match what CI enforces instead of a runner default.
pinned_ready() {
  command -v shellcheck >/dev/null 2>&1 || return 1
  [ "$(shellcheck --version | awk '/^version:/ {print $2; exit}')" = "$REQUIRED" ]
}

test_help_reports_the_complete_interface() {
  local help
  help=$("$LINT" --help) || fail "xo-lint.sh --help failed"
  assert_contains "$help" "--telemetry" "xo-lint.sh --help omitted --telemetry"
  assert_contains "$help" "--required-version" "xo-lint.sh --help omitted --required-version"
  assert_contains "$help" "--list-files" "xo-lint.sh --help omitted --list-files"
  assert_contains "$help" "--help" "xo-lint.sh --help omitted --help"
  assert_contains "$help" "--fast" "xo-lint.sh --help omitted --fast"
  assert_contains "$help" "SC1091" "xo-lint.sh --help omitted the local SC1091 exclusion"
  assert_contains "$help" "SC2034" "xo-lint.sh --help omitted the local SC2034 exclusion"
  assert_contains "$help" "SC2153" "xo-lint.sh --help omitted the local SC2153 exclusion"
  assert_contains "$help" "SC2329" "xo-lint.sh --help omitted the local SC2329 exclusion"
  pass "xo-lint.sh --help reports the complete executable interface"
}

test_list_files_reports_the_shell_inventory() {
  local listed expected
  # CI=true forces the full canonical set regardless of the ambient branch or
  # working-tree diff a local test run happens to have, so this stays a pure
  # inventory check independent of xo-lint.sh's own changed-file mode below.
  listed=$(CI=true "$LINT" --list-files)
  expected=$(find bin bin/backends tests -maxdepth 1 -type f -name '*.sh' -print | LC_ALL=C sort)
  [ "$(printf '%s\n' "$listed" | LC_ALL=C sort)" = "$expected" ] \
    || fail "xo-lint.sh --list-files did not return the complete shell inventory"
  pass "xo-lint.sh --list-files reports the complete shell inventory"
}

# xo_lint_stub_git <fakebin-dir>: install a git stub for the changed-file mode
# tests below. Its answers are driven by env vars the caller sets before
# invoking xo-lint.sh, so those tests can steer git state without depending on
# this worktree's actual branch, remotes, or history:
#   XO_TEST_GIT_INSIDE_WORKTREE  1 (default) or 0
#   XO_TEST_GIT_BRANCH           branch name for `rev-parse --abbrev-ref HEAD`
#   XO_TEST_GIT_HAS_ORIGIN_MAIN  1 (default) or 0
#   XO_TEST_GIT_HAS_MAIN         1 (default) or 0
#   XO_TEST_GIT_MERGE_BASE_OK    1 (default) or 0
#   XO_TEST_GIT_MERGE_BASE       merge-base value to print when OK
#   XO_TEST_GIT_DIFF_FILE        path to a file of NUL-separated changed paths
xo_lint_stub_git() {
  local fakebin=$1
  cat > "$fakebin/git" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "rev-parse --is-inside-work-tree")
    [ "${XO_TEST_GIT_INSIDE_WORKTREE:-1}" = 1 ] || exit 1
    printf 'true\n'
    exit 0
    ;;
  "rev-parse --abbrev-ref HEAD")
    printf '%s\n' "${XO_TEST_GIT_BRANCH:-feature}"
    exit 0
    ;;
  "rev-parse --verify -q origin/main")
    [ "${XO_TEST_GIT_HAS_ORIGIN_MAIN:-1}" = 1 ] && exit 0 || exit 1
    ;;
  "rev-parse --verify -q main")
    [ "${XO_TEST_GIT_HAS_MAIN:-1}" = 1 ] && exit 0 || exit 1
    ;;
  "merge-base "*)
    if [ "${XO_TEST_GIT_MERGE_BASE_OK:-1}" = 1 ]; then
      printf '%s\n' "${XO_TEST_GIT_MERGE_BASE:-fakebase123}"
      exit 0
    fi
    exit 1
    ;;
  "diff --name-only --diff-filter=ACMR -z "*)
    if [ -n "${XO_TEST_GIT_DIFF_FILE:-}" ] && [ -f "$XO_TEST_GIT_DIFF_FILE" ]; then
      cat "$XO_TEST_GIT_DIFF_FILE"
    fi
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
SH
  chmod +x "$fakebin/git"
}

# xo_lint_write_diff_file <file> <path>...: writes NUL-separated changed paths
# in the shape `git diff --name-only -z` produces, for XO_TEST_GIT_DIFF_FILE.
xo_lint_write_diff_file() {
  local file=$1
  shift
  printf '%s\0' "$@" > "$file"
}

# xo_lint_stub_shellcheck <fakebin-dir> <log-file>: install a ShellCheck stub
# that answers --version with the pinned version and otherwise logs the file
# roots it was asked to check (one per line) instead of actually analyzing
# them, so changed-file mode tests can assert exactly which files xo-lint.sh
# selected without depending on real ShellCheck findings. When
# XO_TEST_MODE_LOG is set, it records the effective analysis mode, treating
# ShellCheck's default as full analysis. When XO_TEST_FLAG_LOG is set, it
# records whether --external-sources was passed and the --exclude value.
xo_lint_stub_shellcheck() {
  local fakebin=$1 log=$2
  : > "$log"
  cat > "$fakebin/shellcheck" <<SH
#!/usr/bin/env bash
if [ "\${1:-}" = --version ]; then
  printf 'ShellCheck - shell script analysis tool\nversion: 0.11.0\n'
  exit 0
fi
mode=on
follow=no
exclude=none
while [ "\$#" -gt 0 ] && [ "\$1" != -- ]; do
  case "\$1" in
    --extended-analysis=false) mode=off ;;
    --external-sources) follow=yes ;;
    --exclude=*) exclude=\${1#--exclude=} ;;
    --exclude)
      shift
      exclude=\${1:-none}
      ;;
  esac
  shift
done
if [ -n "\${XO_TEST_MODE_LOG:-}" ]; then
  printf '%s\n' "\$mode" >> "\$XO_TEST_MODE_LOG"
fi
if [ -n "\${XO_TEST_FLAG_LOG:-}" ]; then
  printf 'external-sources=%s\nexclude=%s\n' "\$follow" "\$exclude" >> "\$XO_TEST_FLAG_LOG"
fi
[ "\$#" -eq 0 ] || shift
printf '%s\n' "\$@" >> "$log"
exit 0
SH
  chmod +x "$fakebin/shellcheck"
}

test_fast_mode_disables_extended_analysis() {
  local tmp fakebin log mode_log telemetry fixture out
  tmp=$(xo_test_tmproot xo-lint-fast-mode)
  fakebin=$(xo_fakebin "$tmp")
  fixture="$tmp/fixture.sh"
  log="$tmp/shellcheck.log"
  mode_log="$tmp/mode.log"
  telemetry="$tmp/telemetry.tsv"
  cat > "$fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${1:-ok}"
SH
  chmod +x "$fixture"
  xo_lint_stub_shellcheck "$fakebin" "$log"

  out=$(PATH="$fakebin:$PATH" GITHUB_ACTIONS='' CI='' XO_LINT_JOBS=1 \
    XO_TEST_MODE_LOG="$mode_log" "$LINT" --fast --telemetry "$telemetry" "$fixture" 2>&1) \
    || fail "fast lint mode failed"$'\n'"$out"
  [ "$(cat "$mode_log")" = off ] \
    || fail "fast lint mode did not disable extended analysis"
  [ "$(cat "$log")" = "$fixture" ] \
    || fail "fast lint mode did not lint the requested root"
  assert_grep $'analysis_mode\tfast' "$telemetry" "telemetry did not record fast analysis mode"
  pass "xo-lint.sh --fast disables ShellCheck extended analysis"
}

test_ci_defaults_to_full_analysis() {
  local tmp fakebin log mode_log fixture out
  tmp=$(xo_test_tmproot xo-lint-ci-analysis)
  fakebin=$(xo_fakebin "$tmp")
  fixture="$tmp/fixture.sh"
  log="$tmp/shellcheck.log"
  mode_log="$tmp/mode.log"
  cat > "$fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${1:-ok}"
SH
  chmod +x "$fixture"
  xo_lint_stub_shellcheck "$fakebin" "$log"

  out=$(PATH="$fakebin:$PATH" CI=true GITHUB_ACTIONS=true XO_LINT_FAST=1 XO_LINT_JOBS=1 \
    XO_TEST_MODE_LOG="$mode_log" "$LINT" "$fixture" 2>&1) \
    || fail "CI full lint mode failed"$'\n'"$out"
  [ "$(cat "$mode_log")" = on ] \
    || fail "CI default did not keep full ShellCheck analysis"
  pass "xo-lint.sh keeps full ShellCheck analysis by default in CI"
}

test_ci_rejects_explicit_fast_mode() {
  local tmp fakebin log fixture out rc
  tmp=$(xo_test_tmproot xo-lint-ci-reject-fast)
  fakebin=$(xo_fakebin "$tmp")
  fixture="$tmp/fixture.sh"
  log="$tmp/shellcheck.log"
  cat > "$fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${1:-ok}"
SH
  chmod +x "$fixture"
  xo_lint_stub_shellcheck "$fakebin" "$log"

  rc=0
  out=$(PATH="$fakebin:$PATH" CI=true GITHUB_ACTIONS=true XO_LINT_JOBS=1 \
    "$LINT" --fast "$fixture" 2>&1) || rc=$?
  [ "$rc" -eq 2 ] \
    || fail "CI accepted explicit fast lint mode (exit $rc)"$'\n'"$out"
  assert_contains "$out" "--fast is local-only" \
    "CI fast-mode rejection did not explain the policy"
  [ ! -s "$log" ] || fail "CI invoked ShellCheck after rejecting fast mode"
  pass "xo-lint.sh rejects explicit --fast mode in CI"
}

test_fast_mode_catches_a_real_lint_defect() {
  if ! pinned_ready; then
    pass "SKIP (ShellCheck $REQUIRED not resolved): fast lint-defect regression check"
    return
  fi
  local tmp bad out rc
  tmp=$(xo_test_tmproot xo-lint-fast-bad)
  bad="$tmp/bad.sh"
  cat > "$bad" <<'SH'
#!/usr/bin/env bash
foo() {
  local a= b=
  echo "$a$b"
}
foo
SH
  rc=0
  out=$(GITHUB_ACTIONS='' CI='' "$LINT" --fast "$bad" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "fast lint mode passed a known-bad fixture"$'\n'"$out"
  assert_contains "$out" "SC1007" "fast lint mode did not report the expected ShellCheck finding"
  pass "xo-lint.sh --fast catches an ordinary shell lint defect"
}

test_changed_mode_lints_only_the_changed_file() {
  local tmp fakebin log diff_file out target
  tmp=$(xo_test_tmproot xo-lint-changed)
  fakebin=$(xo_fakebin "$tmp")
  xo_lint_stub_git "$fakebin"
  log="$tmp/shellcheck.log"
  xo_lint_stub_shellcheck "$fakebin" "$log"
  diff_file="$tmp/diff.nul"
  target="bin/xo-install-shellcheck.sh"
  xo_lint_write_diff_file "$diff_file" "$target" "README.md"

  # Clear the ambient CI/GITHUB_ACTIONS signals so changed-file mode is actually
  # exercised: a CI run sets them and would otherwise force the full lint here.
  out=$(PATH="$fakebin:$PATH" GITHUB_ACTIONS='' CI='' XO_LINT_JOBS=1 \
    XO_TEST_GIT_BRANCH=feature \
    XO_TEST_GIT_DIFF_FILE="$diff_file" "$LINT" 2>&1) \
    || fail "changed-mode lint run failed"$'\n'"$out"
  [ "$(cat "$log")" = "$target" ] \
    || fail "changed-mode lint did not run ShellCheck on exactly the changed file"$'\n'"logged: $(cat "$log")"
  pass "xo-lint.sh changed mode lints only the changed canonical file"
}

test_ci_forces_full_lint_even_with_empty_diff() {
  local listed expected
  # No git stub: CI=true must short-circuit xo-lint.sh's mode selection before
  # it ever consults git, so this proves CI wins regardless of local diff state.
  listed=$(CI=true "$LINT" --list-files)
  expected=$(find bin bin/backends tests -maxdepth 1 -type f -name '*.sh' -print | LC_ALL=C sort)
  [ "$(printf '%s\n' "$listed" | LC_ALL=C sort)" = "$expected" ] \
    || fail "CI=true did not force the full canonical file set"
  pass "xo-lint.sh forces a full lint in CI even when the local diff would be empty"
}

test_main_branch_forces_full_lint() {
  local tmp fakebin listed expected
  tmp=$(xo_test_tmproot xo-lint-main-full)
  fakebin=$(xo_fakebin "$tmp")
  xo_lint_stub_git "$fakebin"

  # Clear CI/GITHUB_ACTIONS so the on-main branch is what forces the full lint,
  # not the ambient CI signal a real CI run would otherwise supply.
  listed=$(PATH="$fakebin:$PATH" GITHUB_ACTIONS='' CI='' \
    XO_TEST_GIT_BRANCH=main "$LINT" --list-files)
  expected=$(find bin bin/backends tests -maxdepth 1 -type f -name '*.sh' -print | LC_ALL=C sort)
  [ "$(printf '%s\n' "$listed" | LC_ALL=C sort)" = "$expected" ] \
    || fail "xo-lint.sh did not force a full lint when HEAD is on main"
  pass "xo-lint.sh forces a full lint when HEAD is on main"
}

test_explicit_path_bypasses_changed_logic() {
  local tmp fakebin log out target
  tmp=$(xo_test_tmproot xo-lint-explicit-override)
  fakebin=$(xo_fakebin "$tmp")
  xo_lint_stub_git "$fakebin"
  log="$tmp/shellcheck.log"
  xo_lint_stub_shellcheck "$fakebin" "$log"
  target="bin/xo-install-shellcheck.sh"

  # The git stub reports a broken merge-base, which would force a full lint
  # under the no-args default. Clearing CI/GITHUB_ACTIONS keeps changed-file
  # selection live so this proves the explicit path bypasses it, not that CI
  # already forced full mode. An explicit path must never even consult git.
  out=$(PATH="$fakebin:$PATH" GITHUB_ACTIONS='' CI='' XO_LINT_JOBS=1 \
    XO_TEST_GIT_MERGE_BASE_OK=0 \
    "$LINT" "$target" 2>&1) || fail "explicit-path lint failed"$'\n'"$out"
  [ "$(cat "$log")" = "$target" ] \
    || fail "explicit path lint did not run on exactly the requested file"$'\n'"logged: $(cat "$log")"
  pass "xo-lint.sh explicit paths bypass changed-file mode selection"
}

test_zero_changed_files_exits_clean() {
  local tmp fakebin diff_file out rc
  tmp=$(xo_test_tmproot xo-lint-zero-changed)
  fakebin=$(xo_fakebin "$tmp")
  xo_lint_stub_git "$fakebin"
  diff_file="$tmp/diff.nul"
  : > "$diff_file"

  rc=0
  # Clear CI/GITHUB_ACTIONS so changed-file mode runs and can reach the empty
  # target set; a CI run would otherwise force a full lint instead.
  out=$(PATH="$fakebin:$PATH" GITHUB_ACTIONS='' CI='' XO_TEST_GIT_BRANCH=feature \
    XO_TEST_GIT_DIFF_FILE="$diff_file" "$LINT" 2>&1) || rc=$?
  [ "$rc" -eq 0 ] || fail "zero changed lint targets must exit 0, got $rc"$'\n'"$out"
  assert_contains "$out" "ShellCheck 0.11.0" "zero-changed run did not print the ShellCheck version line"
  assert_contains "$out" "no changed lint targets" "zero-changed run did not note the empty target set"
  assert_contains "$out" "workflow files valid" \
    "zero-changed run skipped workflow YAML validation"
  pass "xo-lint.sh exits 0 with a note when the local branch has no changed lint targets"
}

test_list_files_respects_changed_mode() {
  local tmp fakebin diff_file listed
  tmp=$(xo_test_tmproot xo-lint-list-changed)
  fakebin=$(xo_fakebin "$tmp")
  xo_lint_stub_git "$fakebin"
  diff_file="$tmp/diff.nul"
  # A real canonical file, a non-canonical file, and a canonical-looking path
  # that does not exist: only the first should survive into the listed set.
  xo_lint_write_diff_file "$diff_file" \
    "tests/xo-lint.test.sh" "docs/README.md" "bin/definitely-not-real-file.sh"

  # Clear CI/GITHUB_ACTIONS so --list-files reflects the changed set rather than
  # the full canonical set a CI run's ambient signals would otherwise force.
  listed=$(PATH="$fakebin:$PATH" GITHUB_ACTIONS='' CI='' XO_TEST_GIT_BRANCH=feature \
    XO_TEST_GIT_DIFF_FILE="$diff_file" "$LINT" --list-files)
  [ "$listed" = "tests/xo-lint.test.sh" ] \
    || fail "--list-files did not report the would-be changed set in changed mode"$'\n'"got: $listed"
  pass "xo-lint.sh --list-files reports the would-be changed set in changed mode"
}

xo_lint_assert_flag_log() {
  local flag_log=$1 expected_follow=$2 expected_exclude=$3
  [ -s "$flag_log" ] || fail "ShellCheck was not invoked; flag log is empty"
  awk -v follow="$expected_follow" -v exclude="$expected_exclude" '
    BEGIN { bad=0; saw=0 }
    /^external-sources=/ { saw=1; if ($0 != "external-sources=" follow) bad=1 }
    /^exclude=/ { if ($0 != "exclude=" exclude) bad=1 }
    END { exit (saw && !bad) ? 0 : 1 }
  ' "$flag_log" \
    || fail "ShellCheck flags were not external-sources=$expected_follow exclude=$expected_exclude"$'\n'"$(cat "$flag_log")"
}

test_changed_mode_drops_external_sources_and_excludes_cross_file_codes() {
  local tmp fakebin log flag_log mode_log diff_file telemetry out target
  tmp=$(xo_test_tmproot xo-lint-local-nox)
  fakebin=$(xo_fakebin "$tmp")
  xo_lint_stub_git "$fakebin"
  log="$tmp/shellcheck.log"
  flag_log="$tmp/flags.log"
  mode_log="$tmp/mode.log"
  telemetry="$tmp/telemetry.tsv"
  xo_lint_stub_shellcheck "$fakebin" "$log"
  diff_file="$tmp/diff.nul"
  target="bin/xo-afk-launch.sh"
  xo_lint_write_diff_file "$diff_file" "$target"

  out=$(PATH="$fakebin:$PATH" GITHUB_ACTIONS='' CI='' XO_LINT_JOBS=1 \
    XO_TEST_GIT_BRANCH=feature \
    XO_TEST_GIT_DIFF_FILE="$diff_file" \
    XO_TEST_FLAG_LOG="$flag_log" XO_TEST_MODE_LOG="$mode_log" \
    "$LINT" --telemetry "$telemetry" 2>&1) \
    || fail "changed-mode local lint failed"$'\n'"$out"
  [ "$(cat "$log")" = "$target" ] \
    || fail "changed-mode lint did not run ShellCheck on exactly the changed file"$'\n'"logged: $(cat "$log")"
  [ "$(cat "$mode_log")" = on ] \
    || fail "changed-mode local lint disabled dataflow analysis"
  xo_lint_assert_flag_log "$flag_log" no "SC1091,SC2034,SC2153,SC2329"
  assert_contains "$out" "source following disabled" \
    "changed-mode local lint did not disclose dropped source following"
  assert_grep $'analysis_mode\tlocal' "$telemetry" \
    "telemetry did not record local analysis mode"
  assert_grep $'source_directives\t4' "$telemetry" \
    "telemetry did not count the changed root's source directives"
  assert_grep $'source_followed_directives\t0' "$telemetry" \
    "telemetry reported followed sources in no-external-sources mode"
  pass "xo-lint.sh changed mode drops source following and excludes cross-file codes"
}

test_changed_mode_invokes_shellcheck_once_per_root() {
  local tmp fakebin log flag_log diff_file out first second invocation_count
  tmp=$(xo_test_tmproot xo-lint-local-per-root)
  fakebin=$(xo_fakebin "$tmp")
  xo_lint_stub_git "$fakebin"
  log="$tmp/shellcheck.log"
  flag_log="$tmp/flags.log"
  xo_lint_stub_shellcheck "$fakebin" "$log"
  diff_file="$tmp/diff.nul"
  first="bin/xo-install-shellcheck.sh"
  second="bin/xo-lint-workflows.sh"
  xo_lint_write_diff_file "$diff_file" "$first" "$second"

  out=$(PATH="$fakebin:$PATH" GITHUB_ACTIONS='' CI='' XO_LINT_JOBS=1 \
    XO_TEST_GIT_BRANCH=feature XO_TEST_GIT_DIFF_FILE="$diff_file" \
    XO_TEST_FLAG_LOG="$flag_log" "$LINT" 2>&1) \
    || fail "changed-mode per-root lint failed"$'\n'"$out"
  [ "$(LC_ALL=C sort "$log")" = "$first"$'\n'"$second" ] \
    || fail "changed-mode lint did not analyze both changed roots"$'\n'"logged: $(cat "$log")"
  invocation_count=$(grep -c '^external-sources=' "$flag_log" || true)
  [ "$invocation_count" -eq 2 ] \
    || fail "changed-mode lint used $invocation_count ShellCheck calls for two roots"
  xo_lint_assert_flag_log "$flag_log" no "SC1091,SC2034,SC2153,SC2329"
  pass "xo-lint.sh changed mode invokes ShellCheck once per root"
}

test_ci_keeps_external_sources_without_local_exclusions() {
  local tmp fakebin log flag_log mode_log fixture out
  tmp=$(xo_test_tmproot xo-lint-ci-follow)
  fakebin=$(xo_fakebin "$tmp")
  fixture="$tmp/fixture.sh"
  log="$tmp/shellcheck.log"
  flag_log="$tmp/flags.log"
  mode_log="$tmp/mode.log"
  cat > "$fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${1:-ok}"
SH
  xo_lint_stub_shellcheck "$fakebin" "$log"

  out=$(PATH="$fakebin:$PATH" CI=true GITHUB_ACTIONS=true XO_LINT_JOBS=1 \
    XO_TEST_FLAG_LOG="$flag_log" XO_TEST_MODE_LOG="$mode_log" \
    "$LINT" "$fixture" 2>&1) \
    || fail "CI lint with explicit path failed"$'\n'"$out"
  [ "$(cat "$mode_log")" = on ] \
    || fail "CI lint disabled dataflow analysis"
  xo_lint_assert_flag_log "$flag_log" yes none
  pass "xo-lint.sh CI keeps source following without the local exclusion list"
}

test_main_branch_keeps_external_sources() {
  local tmp fakebin log flag_log out
  tmp=$(xo_test_tmproot xo-lint-main-follow)
  fakebin=$(xo_fakebin "$tmp")
  xo_lint_stub_git "$fakebin"
  log="$tmp/shellcheck.log"
  flag_log="$tmp/flags.log"
  xo_lint_stub_shellcheck "$fakebin" "$log"

  out=$(PATH="$fakebin:$PATH" GITHUB_ACTIONS='' CI='' XO_LINT_JOBS=1 \
    XO_TEST_GIT_BRANCH=main \
    XO_TEST_FLAG_LOG="$flag_log" "$LINT" 2>&1) \
    || fail "main-branch lint failed"$'\n'"$out"
  xo_lint_assert_flag_log "$flag_log" yes none
  pass "xo-lint.sh on main keeps source following without the local exclusion list"
}

test_merge_base_less_keeps_external_sources() {
  local tmp fakebin log flag_log out
  tmp=$(xo_test_tmproot xo-lint-nomergebase-follow)
  fakebin=$(xo_fakebin "$tmp")
  xo_lint_stub_git "$fakebin"
  log="$tmp/shellcheck.log"
  flag_log="$tmp/flags.log"
  xo_lint_stub_shellcheck "$fakebin" "$log"

  out=$(PATH="$fakebin:$PATH" GITHUB_ACTIONS='' CI='' XO_LINT_JOBS=1 \
    XO_TEST_GIT_BRANCH=feature XO_TEST_GIT_MERGE_BASE_OK=0 \
    XO_TEST_FLAG_LOG="$flag_log" "$LINT" 2>&1) \
    || fail "merge-base-less lint failed"$'\n'"$out"
  xo_lint_assert_flag_log "$flag_log" yes none
  pass "xo-lint.sh without a merge-base keeps source following without the local exclusion list"
}

test_explicit_path_keeps_external_sources() {
  local tmp fakebin log flag_log out target
  tmp=$(xo_test_tmproot xo-lint-explicit-follow)
  fakebin=$(xo_fakebin "$tmp")
  xo_lint_stub_git "$fakebin"
  log="$tmp/shellcheck.log"
  flag_log="$tmp/flags.log"
  xo_lint_stub_shellcheck "$fakebin" "$log"
  target="bin/xo-install-shellcheck.sh"

  out=$(PATH="$fakebin:$PATH" GITHUB_ACTIONS='' CI='' XO_LINT_JOBS=1 \
    XO_TEST_GIT_BRANCH=feature \
    XO_TEST_FLAG_LOG="$flag_log" "$LINT" "$target" 2>&1) \
    || fail "explicit-path lint failed"$'\n'"$out"
  xo_lint_assert_flag_log "$flag_log" yes none
  pass "xo-lint.sh explicit paths keep source following"
}

test_fast_mode_on_a_local_branch_keeps_source_following() {
  local tmp fakebin log flag_log mode_log diff_file out target
  tmp=$(xo_test_tmproot xo-lint-fast-follow)
  fakebin=$(xo_fakebin "$tmp")
  xo_lint_stub_git "$fakebin"
  log="$tmp/shellcheck.log"
  flag_log="$tmp/flags.log"
  mode_log="$tmp/mode.log"
  xo_lint_stub_shellcheck "$fakebin" "$log"
  diff_file="$tmp/diff.nul"
  target="bin/xo-install-shellcheck.sh"
  xo_lint_write_diff_file "$diff_file" "$target"

  out=$(PATH="$fakebin:$PATH" GITHUB_ACTIONS='' CI='' XO_LINT_JOBS=1 \
    XO_TEST_GIT_BRANCH=feature \
    XO_TEST_GIT_DIFF_FILE="$diff_file" \
    XO_TEST_FLAG_LOG="$flag_log" XO_TEST_MODE_LOG="$mode_log" \
    "$LINT" --fast 2>&1) \
    || fail "fast local-branch lint failed"$'\n'"$out"
  [ "$(cat "$mode_log")" = off ] \
    || fail "fast local-branch lint did not disable extended analysis"
  xo_lint_assert_flag_log "$flag_log" yes none
  pass "xo-lint.sh --fast on a local branch keeps source following"
}

test_changed_mode_hides_cross_file_codes_that_ci_still_sees() {
  if ! pinned_ready; then
    pass "SKIP (ShellCheck $REQUIRED not resolved): changed-mode exclusion behavior"
    return
  fi
  local tmp fakebin diff_file fixture out rc
  tmp=$(xo_test_tmproot xo-lint-local-exclude-behavior)
  fixture="$ROOT/tests/xo-lint-local-exclude-fixture.test.sh"
  printf '%s\n' "$fixture" >> "$XO_TEST_CLEANUP_REGISTRY"
  cat > "$fixture" <<'SH'
#!/usr/bin/env bash
# Assigned here and only consumed by a library the local gate does not follow.
cross_file_only=1
outer() {
  (
    # Defined here and only invoked by a library the local gate does not follow.
    cross_file_helper() {
      printf 'ok\n'
    }
    printf 'hi\n'
  )
}
outer
SH
  fakebin=$(xo_fakebin "$tmp")
  xo_lint_stub_git "$fakebin"
  diff_file="$tmp/diff.nul"
  xo_lint_write_diff_file "$diff_file" "tests/xo-lint-local-exclude-fixture.test.sh"

  rc=0
  out=$(PATH="$fakebin:$PATH" GITHUB_ACTIONS='' CI='' XO_LINT_JOBS=1 \
    XO_TEST_GIT_BRANCH=feature \
    XO_TEST_GIT_DIFF_FILE="$diff_file" "$LINT" 2>&1) || rc=$?
  [ "$rc" -eq 0 ] \
    || fail "changed-mode local lint failed a cross-file-only fixture"$'\n'"$out"
  assert_not_contains "$out" "SC2034" "changed-mode local lint still reported SC2034"
  assert_not_contains "$out" "SC2329" "changed-mode local lint still reported SC2329"

  rc=0
  out=$("$LINT" "$fixture" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "explicit-path lint passed a cross-file-only fixture"$'\n'"$out"
  assert_contains "$out" "SC2034" "explicit-path lint did not keep SC2034"
  assert_contains "$out" "SC2329" "explicit-path lint did not keep SC2329"
  rm -f "$fixture"
  pass "xo-lint.sh changed mode excludes cross-file codes that explicit paths still report"
}

# One ShellCheck process per root. Passing the whole canonical set in a
# single invocation still follows in-set sources and is not the no-x posture.
xo_lint_nox_one_root() {
  local index=$1 path=$2 outdir=$3
  shellcheck --norc --format gcc -- "$path" > "$outdir/$index" || true
}

test_local_exclusion_list_covers_every_no_external_sources_code() {
  if ! pinned_ready; then
    pass "SKIP (ShellCheck $REQUIRED not resolved): local exclusion completeness"
    return
  fi
  local tmp files_file out unexpected code path found i batch
  local -a files
  tmp=$(xo_test_tmproot xo-lint-nox-complete)
  files_file="$tmp/files"
  CI=true "$LINT" --list-files > "$files_file"
  [ -s "$files_file" ] || fail "CI --list-files returned no canonical lint roots"
  files=()
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    files+=("$path")
  done < "$files_file"
  [ "${#files[@]}" -gt 0 ] || fail "CI --list-files returned no readable lint roots"
  mkdir -p "$tmp/gcc"
  i=0
  batch=0
  for path in "${files[@]}"; do
    i=$((i + 1))
    xo_lint_nox_one_root "$i" "$path" "$tmp/gcc" &
    batch=$((batch + 1))
    if [ "$batch" -eq 4 ]; then
      wait
      batch=0
    fi
  done
  wait
  found=$(find "$tmp/gcc" -type f | wc -l | tr -d '[:space:]')
  [ "$found" = "${#files[@]}" ] \
    || fail "completeness sweep linted $found roots, expected ${#files[@]}"
  out=$(cat "$tmp/gcc"/* 2>/dev/null || true)
  unexpected=
  while IFS= read -r code; do
    [ -n "$code" ] || continue
    case "$code" in
      SC1091|SC2034|SC2153|SC2329) ;;
      *) unexpected="${unexpected}${unexpected:+ }$code" ;;
    esac
  done < <(printf '%s\n' "$out" | sed -n 's/.*\[\(SC[0-9][0-9]*\)\].*/\1/p' | LC_ALL=C sort -u)
  [ -z "$unexpected" ] \
    || fail "no-external-sources pass emitted codes outside the local exclusion list: $unexpected"
  pass "local exclusion list covers every no-external-sources ShellCheck code"
}

test_pins_an_explicit_version() {
  [ -n "$REQUIRED" ] || fail "xo-lint.sh --required-version printed nothing"
  # The captain-agreed pin: adopt ShellCheck 0.11.0's rule set consistently,
  # which is also what drops the upstream-retired, false-positive-prone SC2015.
  assert_contains "$REQUIRED" "0.11.0" "xo-lint.sh must pin ShellCheck 0.11.0"
  pass "xo-lint.sh pins an explicit ShellCheck version ($REQUIRED)"
}

test_installer_retries_transient_download_failure() {
  local tmp fakebin destination out
  tmp=$(xo_test_tmproot xo-shellcheck-download)
  fakebin=$(xo_fakebin "$tmp")
  destination="$tmp/bin"

  xo_install_stub_uname "$fakebin"
  xo_install_stub_curl "$fakebin"
  xo_install_stub_hasher "$fakebin" sha256sum
  xo_install_stub_tar_shellcheck "$fakebin"
  xo_install_stub_sleep "$fakebin"

  # Reproduce the CI incident: the release endpoint returned 503 for all three
  # formerly configured attempts before recovering. Force linux/x86_64 so the
  # retry path stays the CI archive even when this suite runs on macOS.
  out=$(CURL_COUNT="$tmp/curl-count" CURL_FAIL_UNTIL=3 \
    SHA256_STUB_HASH="$SHELLCHECK_SHA_LINUX_X86_64" \
    XO_TEST_UNAME_S=Linux XO_TEST_UNAME_M=x86_64 \
    PATH="$fakebin:$PATH" "$INSTALLER" "$destination" 2>&1) \
    || fail "installer did not recover from a transient download failure"$'\n'"$out"
  [ "$(cat "$tmp/curl-count")" -eq 4 ] || fail "installer did not recover after three failed downloads"
  assert_contains "$out" "download attempt 3 failed; retrying" "installer did not disclose its third retry"
  [ -x "$destination/shellcheck" ] || fail "installer did not install ShellCheck after retrying"
  pass "ShellCheck installer retries a transient download failure"
}

test_installer_selects_platform_archive_url_and_checksum() {
  local tmp fakebin destination out url_log uname_s uname_m archive sha
  tmp=$(xo_test_tmproot xo-shellcheck-platform)
  fakebin=$(xo_fakebin "$tmp")
  destination="$tmp/bin"
  url_log="$tmp/curl-url.log"

  xo_install_stub_uname "$fakebin"
  xo_install_stub_curl "$fakebin"
  xo_install_stub_hasher "$fakebin" sha256sum
  xo_install_stub_tar_shellcheck "$fakebin"
  xo_install_stub_sleep "$fakebin"

  while IFS=$'\t' read -r uname_s uname_m archive sha; do
    [ -n "$uname_s" ] || continue
    rm -rf "$destination"
    : > "$url_log"
    out=$(CURL_URL_LOG="$url_log" SHA256_STUB_HASH="$sha" \
      XO_TEST_UNAME_S="$uname_s" XO_TEST_UNAME_M="$uname_m" \
      PATH="$fakebin:$PATH" "$INSTALLER" "$destination" 2>&1) \
      || fail "installer failed for ${uname_s}/${uname_m}"$'\n'"$out"
    assert_contains "$(cat "$url_log")" "$archive" \
      "installer did not download $archive for ${uname_s}/${uname_m}"
    assert_contains "$(cat "$url_log")" \
      "https://github.com/koalaman/shellcheck/releases/download/v${REQUIRED}/${archive}" \
      "installer used the wrong URL for ${uname_s}/${uname_m}"
    [ -x "$destination/shellcheck" ] || fail "installer did not install ShellCheck for ${uname_s}/${uname_m}"
  done <<EOF
Linux	x86_64	shellcheck-v${REQUIRED}.linux.x86_64.tar.xz	$SHELLCHECK_SHA_LINUX_X86_64
Linux	amd64	shellcheck-v${REQUIRED}.linux.x86_64.tar.xz	$SHELLCHECK_SHA_LINUX_X86_64
Linux	aarch64	shellcheck-v${REQUIRED}.linux.aarch64.tar.xz	$SHELLCHECK_SHA_LINUX_AARCH64
Linux	arm64	shellcheck-v${REQUIRED}.linux.aarch64.tar.xz	$SHELLCHECK_SHA_LINUX_AARCH64
Darwin	x86_64	shellcheck-v${REQUIRED}.darwin.x86_64.tar.xz	$SHELLCHECK_SHA_DARWIN_X86_64
Darwin	amd64	shellcheck-v${REQUIRED}.darwin.x86_64.tar.xz	$SHELLCHECK_SHA_DARWIN_X86_64
Darwin	arm64	shellcheck-v${REQUIRED}.darwin.aarch64.tar.xz	$SHELLCHECK_SHA_DARWIN_AARCH64
Darwin	aarch64	shellcheck-v${REQUIRED}.darwin.aarch64.tar.xz	$SHELLCHECK_SHA_DARWIN_AARCH64
EOF
  pass "ShellCheck installer selects the official archive, URL, and checksum per OS/arch"
}

test_installer_rejects_wrong_checksum() {
  local tmp fakebin destination out rc
  tmp=$(xo_test_tmproot xo-shellcheck-badsum)
  fakebin=$(xo_fakebin "$tmp")
  destination="$tmp/bin"

  xo_install_stub_uname "$fakebin"
  xo_install_stub_curl "$fakebin"
  xo_install_stub_hasher "$fakebin" sha256sum
  xo_install_stub_tar_shellcheck "$fakebin"
  xo_install_stub_sleep "$fakebin"

  rc=0
  out=$(SHA256_STUB_HASH=0000000000000000000000000000000000000000000000000000000000000000 \
    XO_TEST_UNAME_S=Linux XO_TEST_UNAME_M=x86_64 \
    PATH="$fakebin:$PATH" "$INSTALLER" "$destination" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "installer accepted a wrong checksum"$'\n'"$out"
  assert_contains "$out" "checksum mismatch" "installer did not report a checksum mismatch"
  assert_contains "$out" "shellcheck-v${REQUIRED}.linux.x86_64.tar.xz" \
    "mismatch did not name the selected archive"
  assert_contains "$out" "$SHELLCHECK_SHA_LINUX_X86_64" \
    "mismatch did not name the pinned linux/x86_64 checksum"
  [ ! -e "$destination/shellcheck" ] || fail "installer installed ShellCheck after a checksum mismatch"
  pass "ShellCheck installer rejects a wrong checksum"
}

test_installer_falls_back_to_shasum() {
  local tmp fakebin destination out hasher_log tool
  tmp=$(xo_test_tmproot xo-shellcheck-shasum)
  fakebin=$(xo_fakebin "$tmp")
  destination="$tmp/bin"
  hasher_log="$tmp/hasher.log"

  for tool in bash dirname mktemp rm awk mkdir install cat chmod; do
    ln -s "$(command -v "$tool")" "$fakebin/$tool"
  done
  xo_install_stub_uname "$fakebin"
  xo_install_stub_curl "$fakebin"
  xo_install_stub_hasher "$fakebin" shasum
  xo_install_stub_tar_shellcheck "$fakebin"
  xo_install_stub_sleep "$fakebin"

  # Restricted PATH: shasum is present, sha256sum is not.
  : > "$hasher_log"
  out=$(CURL_URL_LOG="$tmp/curl-url.log" HASHER_LOG="$hasher_log" \
    SHA256_STUB_HASH="$SHELLCHECK_SHA_LINUX_X86_64" \
    XO_TEST_UNAME_S=Linux XO_TEST_UNAME_M=x86_64 \
    PATH="$fakebin" "$INSTALLER" "$destination" 2>&1) \
    || fail "installer did not fall back to shasum -a 256"$'\n'"$out"
  assert_grep 'shasum -a 256' "$hasher_log" "installer did not invoke shasum -a 256"
  [ -x "$destination/shellcheck" ] || fail "installer did not install ShellCheck via shasum"
  pass "ShellCheck installer falls back to shasum -a 256 when sha256sum is absent"
}

test_installer_prefers_sha256sum_over_shasum() {
  local tmp fakebin destination hasher_log
  tmp=$(xo_test_tmproot xo-shellcheck-sha256sum-pref)
  fakebin=$(xo_fakebin "$tmp")
  destination="$tmp/bin"
  hasher_log="$tmp/hasher.log"

  xo_install_stub_uname "$fakebin"
  xo_install_stub_curl "$fakebin"
  xo_install_stub_hasher "$fakebin" sha256sum
  xo_install_stub_hasher "$fakebin" shasum
  xo_install_stub_tar_shellcheck "$fakebin"
  xo_install_stub_sleep "$fakebin"

  : > "$hasher_log"
  PATH="$fakebin:$PATH" HASHER_LOG="$hasher_log" \
    SHA256_STUB_HASH="$SHELLCHECK_SHA_LINUX_X86_64" \
    XO_TEST_UNAME_S=Linux XO_TEST_UNAME_M=x86_64 \
    "$INSTALLER" "$destination" >/dev/null \
    || fail "installer failed when both hashers were present"
  assert_grep 'sha256sum' "$hasher_log" "installer did not prefer sha256sum"
  if grep -q 'shasum' "$hasher_log"; then
    fail "installer invoked shasum even though sha256sum was present"$'\n'"$(cat "$hasher_log")"
  fi
  pass "ShellCheck installer prefers sha256sum when both hashers are present"
}

test_installer_rejects_unsupported_platform() {
  local tmp fakebin destination out rc
  tmp=$(xo_test_tmproot xo-shellcheck-unsupported)
  fakebin=$(xo_fakebin "$tmp")
  destination="$tmp/bin"

  xo_install_stub_uname "$fakebin"
  xo_install_stub_curl "$fakebin"

  rc=0
  out=$(XO_TEST_UNAME_S=FreeBSD XO_TEST_UNAME_M=amd64 \
    PATH="$fakebin:$PATH" "$INSTALLER" "$destination" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "installer accepted an unsupported OS"$'\n'"$out"
  assert_contains "$out" "unsupported platform" "installer did not name the unsupported platform"
  assert_contains "$out" "FreeBSD-amd64" "installer did not report the detected OS/arch"

  rc=0
  out=$(XO_TEST_UNAME_S=Linux XO_TEST_UNAME_M=ppc64le \
    PATH="$fakebin:$PATH" "$INSTALLER" "$destination" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "installer accepted an unsupported architecture"$'\n'"$out"
  assert_contains "$out" "unsupported platform" "installer did not reject linux/ppc64le"
  pass "ShellCheck installer rejects an unsupported OS or architecture"
}

test_missing_shellcheck_fails_closed() {
  local tmp fakebin out rc tool
  tmp=$(xo_test_tmproot xo-lint-noshellcheck)
  fakebin=$(xo_fakebin "$tmp")
  for tool in bash dirname; do
    ln -s "$(command -v "$tool")" "$fakebin/$tool"
  done
  rc=0
  out=$(PATH="$fakebin" CI=true GITHUB_ACTIONS=true "$LINT" 2>&1) || rc=$?
  [ "$rc" -eq 1 ] || fail "missing ShellCheck expected exit 1, got $rc"$'\n'"$out"
  assert_contains "$out" "ShellCheck not found" \
    "missing ShellCheck did not name the required linter"
  assert_contains "$out" "$REQUIRED" \
    "missing ShellCheck did not name the pinned version"
  assert_contains "$out" "xo-install-shellcheck.sh" \
    "missing ShellCheck did not name the pinned installer"
  pass "missing ShellCheck fails closed"
}

test_rejects_wrong_shellcheck_version() {
  # Version-independent: a fake shellcheck reporting a different version must be
  # refused before any lint, proving local and CI cannot silently diverge.
  local tmp fakebin out rc
  tmp=$(xo_test_tmproot xo-lint-ver)
  fakebin=$(xo_fakebin "$tmp")
  cat > "$fakebin/shellcheck" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then
  printf 'ShellCheck - shell script analysis tool\nversion: 0.9.9\nlicense: x\nwebsite: y\n'
  exit 0
fi
exit 0
SH
  chmod +x "$fakebin/shellcheck"
  rc=0
  out=$(PATH="$fakebin:$PATH" "$LINT" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "xo-lint.sh accepted a shellcheck version other than the pin"$'\n'"$out"
  assert_contains "$out" "$REQUIRED" "xo-lint.sh did not name the required version on mismatch"
  assert_contains "$out" "0.9.9" "xo-lint.sh did not report the resolved (wrong) version"
  pass "xo-lint.sh refuses to lint under a non-pinned ShellCheck version"
}

test_catches_a_real_lint_defect() {
  if ! pinned_ready; then
    pass "SKIP (ShellCheck $REQUIRED not resolved): lint-defect regression check"
    return
  fi
  # A script with a genuine ShellCheck finding must make the one owner exit
  # non-zero, proving local now runs real shellcheck instead of the old no-op
  # lint step. We deliberately do NOT assert SC2015 (PR 475's actual failure):
  # ShellCheck removed SC2015 in the pinned 0.11.0, so asserting it would make
  # this test itself version-fragile - the very trap being fixed. SC1007 is a
  # warning present at default severity (and is itself one of the recurring
  # classes that slipped through, PR 474).
  local tmp bad out rc
  tmp=$(xo_test_tmproot xo-lint-bad)
  mkdir -p "$tmp"
  bad="$tmp/bad.sh"
  cat > "$bad" <<'SH'
#!/usr/bin/env bash
foo() {
  local a= b=
  echo "$a$b"
}
foo
SH
  rc=0
  out=$("$LINT" "$bad" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "xo-lint.sh passed a known-bad fixture"$'\n'"$out"
  assert_contains "$out" "SC1007" "xo-lint.sh did not report the expected ShellCheck finding"
  pass "xo-lint.sh catches a real lint defect the old no-op gate passed"
}

test_rejects_direct_beads_cli_invocations() {
  local tmp fakebin log lint_copy invocation out rc
  tmp=$(xo_test_tmproot xo-lint-backend-purity)
  fakebin=$(xo_fakebin "$tmp")
  log="$tmp/shellcheck.log"
  mkdir -p "$tmp/repo/bin/backends" "$tmp/repo/tests"
  lint_copy="$tmp/repo/bin/xo-lint.sh"
  cp "$LINT" "$lint_copy"
  cat > "$tmp/repo/bin/xo-lint-workflows.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cat > "$tmp/repo/bin/backends/noop.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cat > "$tmp/repo/tests/noop.test.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$lint_copy" "$tmp/repo/bin/xo-lint-workflows.sh"
  xo_lint_stub_shellcheck "$fakebin" "$log"

  for invocation in \
    'bd update xo-example --status in_progress' \
    'BD_ACTOR=xo bd update xo-example --status closed' \
    'env bd close xo-example' \
    'env -i BD_ACTOR=xo bd close xo-example' \
    'env -u BD_ACTOR bd close xo-example' \
    'env -- bd close xo-example' \
    '/usr/local/bin/bd close xo-example' \
    '"/usr/local/bin/bd" close xo-example' \
    "'/usr/local/bin/bd' close xo-example" \
    "b'd' close xo-example" \
    "/usr/local/bin/b'd' close xo-example" \
    "\$'bd' close xo-example" \
    '$"bd" close xo-example' \
    "\$'\\x62\\x64' close xo-example" \
    "\$'\\142\\144' close xo-example" \
    "b\$'\\x64' close xo-example"
  do
    printf '#!/usr/bin/env bash\n%s\n' "$invocation" > "$tmp/repo/bin/direct-beads.sh"
    rc=0
    out=$(cd "$tmp/repo" && CI=true PATH="$fakebin:$PATH" "$lint_copy" 2>&1) || rc=$?
    [ "$rc" -ne 0 ] || fail "lint accepted a direct Beads CLI invocation: $invocation"
    assert_contains "$out" "direct Beads CLI invocation bypasses tasks-axi" \
      "lint did not identify the backend-boundary violation: $invocation"
  done
  pass "xo-lint.sh rejects direct Beads CLI invocations in xo core"
}

test_rejects_direct_beads_cli_in_explicit_core_path() {
  local tmp fakebin log lint_copy target spelling out rc
  tmp=$(xo_test_tmproot xo-lint-explicit-backend-purity)
  fakebin=$(xo_fakebin "$tmp")
  log="$tmp/shellcheck.log"
  mkdir -p "$tmp/repo/bin/backends"
  lint_copy="$tmp/repo/bin/xo-lint.sh"
  target="$tmp/repo/bin/direct-beads.sh"
  cp "$LINT" "$lint_copy"
  printf '#!/usr/bin/env bash\nbd close xo-example\n' > "$target"
  chmod +x "$lint_copy"
  xo_lint_stub_shellcheck "$fakebin" "$log"

  for spelling in bin/direct-beads.sh bin/../bin/direct-beads.sh; do
    rc=0
    out=$(cd "$tmp/repo" && PATH="$fakebin:$PATH" "$lint_copy" "$spelling" 2>&1) || rc=$?
    [ "$rc" -ne 0 ] || fail "explicit core path bypassed backend-purity lint: $spelling"
    assert_contains "$out" "direct Beads CLI invocation bypasses tasks-axi" \
      "explicit core path did not report the backend-boundary violation: $spelling"
  done
  pass "xo-lint.sh enforces backend purity for explicit core paths"
}

test_ignores_ambient_shellcheck_opts() {
  if ! pinned_ready; then
    pass "SKIP (ShellCheck $REQUIRED not resolved): ambient options regression check"
    return
  fi
  local tmp bad out rc
  tmp=$(xo_test_tmproot xo-lint-opts)
  mkdir -p "$tmp"
  bad="$tmp/bad.sh"
  cat > "$bad" <<'SH'
#!/usr/bin/env bash
foo() {
  local a= b=
  echo "$a$b"
}
foo
SH
  rc=0
  out=$(SHELLCHECK_OPTS='--exclude=SC1007' "$LINT" "$bad" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "xo-lint.sh allowed ambient SHELLCHECK_OPTS to hide a finding"$'\n'"$out"
  assert_contains "$out" "SC1007" "xo-lint.sh did not neutralize ambient SHELLCHECK_OPTS"
  pass "xo-lint.sh ignores ambient ShellCheck options"
}

test_clean_fixture_passes() {
  if ! pinned_ready; then
    pass "SKIP (ShellCheck $REQUIRED not resolved): clean fixture check"
    return
  fi
  local tmp good rc
  tmp=$(xo_test_tmproot xo-lint-good)
  mkdir -p "$tmp"
  good="$tmp/good.sh"
  cat > "$good" <<'SH'
#!/usr/bin/env bash
set -eu
if [ -n "${1:-}" ] && [ -d "$1" ]; then
  printf 'ok\n'
fi
SH
  rc=0
  "$LINT" "$good" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "xo-lint.sh flagged a clean fixture (exit $rc)"
  pass "xo-lint.sh passes a clean fixture"
}

test_jobs_are_deterministic_and_complete() {
  if ! pinned_ready; then
    pass "SKIP (ShellCheck $REQUIRED not resolved): deterministic bounded jobs check"
    return
  fi
  local tmp good bad_a bad_b out_clean_1 out_clean_2 out_fail_1 out_fail_2 out_fail_2b
  local telemetry telemetry_out cleanup_tmp cleanup_out rc_clean_1 rc_clean_2 rc_fail_1 rc_fail_2 rc_fail_2b rc_bad_jobs
  tmp=$(xo_test_tmproot xo-lint-jobs)
  mkdir -p "$tmp"
  good="$tmp/good.sh"
  bad_a="$tmp/bad-a.sh"
  bad_b="$tmp/bad-b.sh"
  telemetry="$tmp/telemetry.tsv"
  cat > "$good" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${1:-ok}"
SH
  cat > "$bad_a" <<'SH'
#!/usr/bin/env bash
bad_a() {
  local a= b=
  printf '%s\n' "$a$b"
}
SH
  cat > "$bad_b" <<'SH'
#!/usr/bin/env bash
bad_b() {
  printf '%s\n' $1
}
SH

  rc_clean_1=0
  out_clean_1=$(XO_LINT_JOBS=1 "$LINT" "$good" 2>&1) || rc_clean_1=$?
  rc_clean_2=0
  out_clean_2=$(XO_LINT_JOBS=2 "$LINT" "$good" 2>&1) || rc_clean_2=$?
  [ "$rc_clean_1" -eq 0 ] && [ "$rc_clean_2" -eq 0 ] || fail "clean jobs=1/jobs=2 paths must both pass"
  [ "$out_clean_1" = "$out_clean_2" ] || fail "clean jobs=1/jobs=2 output differs"

  rc_fail_1=0
  out_fail_1=$(XO_LINT_JOBS=1 "$LINT" "$bad_a" "$bad_b" 2>&1) || rc_fail_1=$?
  rc_fail_2=0
  out_fail_2=$(XO_LINT_JOBS=2 "$LINT" "$bad_a" "$bad_b" 2>&1) || rc_fail_2=$?
  rc_fail_2b=0
  out_fail_2b=$(XO_LINT_JOBS=2 "$LINT" "$bad_a" "$bad_b" 2>&1) || rc_fail_2b=$?
  [ "$rc_fail_1" -ne 0 ] && [ "$rc_fail_1" -eq "$rc_fail_2" ] && [ "$rc_fail_2" -eq "$rc_fail_2b" ] \
    || fail "failing jobs=1/jobs=2 exit results differ: $rc_fail_1/$rc_fail_2/$rc_fail_2b"
  [ "$out_fail_1" = "$out_fail_2" ] && [ "$out_fail_2" = "$out_fail_2b" ] \
    || fail "failing diagnostics are not byte-identical and deterministic across jobs"
  assert_contains "$out_fail_1" "SC1007" "the first failing root diagnostic was lost"
  assert_contains "$out_fail_1" "SC2086" "the later failing root diagnostic was lost"
  rc_bad_jobs=0
  XO_LINT_JOBS=3 "$LINT" "$good" >/dev/null 2>&1 || rc_bad_jobs=$?
  [ "$rc_bad_jobs" -eq 2 ] || fail "the lint owner must reject unbounded worker counts"

  telemetry_out=$(XO_LINT_JOBS=2 XO_LINT_TELEMETRY="$telemetry" "$LINT" "$good" 2>&1) \
    || fail "telemetry-enabled clean lint failed"
  [ "$telemetry_out" = "$out_clean_2" ] || fail "quiet telemetry changed routine lint output"
  assert_grep $'format\txo-lint-telemetry-v1' "$telemetry" "telemetry format marker is missing"
  assert_grep $'analysis_mode\tfull' "$telemetry" "telemetry did not record full analysis mode"
  assert_grep $'jobs\t2' "$telemetry" "telemetry did not record bounded jobs"
  assert_grep $'root_count\t1' "$telemetry" "telemetry did not record root count"
  assert_grep $'wall_seconds\t' "$telemetry" "telemetry did not record wall time"
  assert_grep $'user_seconds\t' "$telemetry" "telemetry did not record user CPU"
  assert_grep $'system_seconds\t' "$telemetry" "telemetry did not record system CPU"
  assert_grep $'max_worker_rss_kib\t' "$telemetry" "telemetry did not record maximum RSS"
  assert_grep $'source_boundary_directives\t' "$telemetry" "telemetry did not record source-graph boundaries"
  assert_grep $'shellcheck_processes_start\t' "$telemetry" "telemetry did not record competing ShellCheck conditions"

  cleanup_tmp="$tmp/lint-tmp"
  mkdir -p "$cleanup_tmp"
  cleanup_out=$(TMPDIR="$cleanup_tmp" XO_LINT_JOBS=2 "$LINT" "$good" 2>&1) \
    || fail "cleanup fixture lint failed"
  [ "$cleanup_out" = "$out_clean_2" ] || fail "cleanup fixture changed routine diagnostics"
  [ -z "$(find "$cleanup_tmp" -mindepth 1 -maxdepth 1 -name 'xo-lint.*' -print -quit)" ] \
    || fail "bounded lint left temporary worker state behind"
  pass "jobs=1 and jobs=2 preserve deterministic diagnostics, failures, cleanup bounds, and quiet telemetry"
}

test_worker_trees_stop_on_signal() {
  local tmp fakebin fixture jobs telemetry lint_tmp pid_file out_file telemetry_file
  local parent_pid shellcheck_pid i parent_rc survivor
  tmp=$(xo_test_tmproot xo-lint-signal)
  mkdir -p "$tmp"
  fakebin=$(xo_fakebin "$tmp")
  fixture="$tmp/good.sh"
  cat > "$fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${1:-ok}"
SH
  cat > "$fakebin/shellcheck" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  printf 'ShellCheck - shell script analysis tool\nversion: 0.11.0\n'
  exit 0
fi
printf '%s\n' "$$" > "$XO_TEST_SHELLCHECK_PID"
trap 'exit 143' HUP INT TERM
while :; do
  sleep 1
done
SH
  chmod +x "$fakebin/shellcheck"

  for jobs in 1 2; do
    for telemetry in off on; do
      lint_tmp="$tmp/lint-$jobs-$telemetry"
      pid_file="$tmp/shellcheck-$jobs-$telemetry.pid"
      out_file="$tmp/output-$jobs-$telemetry"
      telemetry_file=
      mkdir -p "$lint_tmp"
      if [ "$telemetry" = on ]; then
        telemetry_file="$tmp/telemetry-$jobs.tsv"
      fi
      PATH="$fakebin:$PATH" TMPDIR="$lint_tmp" XO_LINT_JOBS="$jobs" \
        XO_LINT_TELEMETRY="$telemetry_file" XO_TEST_SHELLCHECK_PID="$pid_file" \
        "$LINT" "$fixture" > "$out_file" 2>&1 &
      parent_pid=$!
      i=0
      while [ "$i" -lt 500 ] && [ ! -s "$pid_file" ]; do
        kill -0 "$parent_pid" 2>/dev/null || break
        sleep 0.01
        i=$((i + 1))
      done
      [ -s "$pid_file" ] || {
        kill -TERM "$parent_pid" 2>/dev/null || true
        wait "$parent_pid" 2>/dev/null || true
        fail "jobs=$jobs telemetry=$telemetry did not start ShellCheck"
      }
      shellcheck_pid=$(cat "$pid_file")
      kill -TERM "$parent_pid" 2>/dev/null \
        || fail "jobs=$jobs telemetry=$telemetry parent could not be interrupted"
      parent_rc=0
      wait "$parent_pid" 2>/dev/null || parent_rc=$?
      survivor=0
      i=0
      while [ "$i" -lt 100 ] && kill -0 "$shellcheck_pid" 2>/dev/null; do
        sleep 0.01
        i=$((i + 1))
      done
      if kill -0 "$shellcheck_pid" 2>/dev/null; then
        survivor=1
        kill -KILL "$shellcheck_pid" 2>/dev/null || true
      fi
      [ "$parent_rc" -eq 143 ] \
        || fail "jobs=$jobs telemetry=$telemetry signal exit was $parent_rc, expected 143"
      [ "$survivor" -eq 0 ] \
        || fail "jobs=$jobs telemetry=$telemetry left ShellCheck running"
      [ -z "$(find "$lint_tmp" -mindepth 1 -maxdepth 1 -name 'xo-lint.*' -print -quit)" ] \
        || fail "jobs=$jobs telemetry=$telemetry left temporary worker state"
    done
  done
  pass "jobs=1 and jobs=2 stop complete worker trees with and without telemetry"
}

test_seeded_module_boundary_parity() {
  if ! pinned_ready; then
    pass "SKIP (ShellCheck $REQUIRED not resolved): seeded source-boundary parity check"
    return
  fi
  local tmp rel adapter dispatcher dep owner test_root out rc
  tmp=$(mktemp -d "$ROOT/.xo-lint-parity.XXXXXX")
  if [ "${#XO_TEST_CLEANUP_DIRS[@]}" -eq 0 ]; then
    trap xo_test_cleanup EXIT
  fi
  XO_TEST_CLEANUP_DIRS+=("$tmp")
  rel=${tmp#"$ROOT/"}
  adapter="$tmp/adapter.sh"
  dispatcher="$tmp/dispatcher.sh"
  dep="$tmp/owner-dep.sh"
  owner="$tmp/owner.sh"
  test_root="$tmp/test-local.sh"

  cat > "$adapter" <<'SH'
#!/usr/bin/env bash
adapter_bad() {
  rm $1
}
SH
  cat > "$dispatcher" <<SH
#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$adapter"
dispatcher_bad() {
  local a= b=
  printf '%s\n' "\$a\$b"
}
SH
  cat > "$dep" <<'SH'
#!/usr/bin/env bash
owner_dependency_value=ok
SH
  cat > "$owner" <<SH
#!/usr/bin/env bash
# shellcheck source=$rel/owner-dep.sh
. "$dep"
owner_bad() {
  printf '%s\n' "\$owner_dependency_value"
  cd "\$1"
}
SH
  cat > "$test_root" <<SH
#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$owner"
test_local_bad() {
  local output=\$(printf ok)
  printf '%s\n' "\$output"
}
SH

  rc=0
  out=$(XO_LINT_JOBS=2 "$LINT" "$dispatcher" "$adapter" "$owner" "$test_root" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "seeded module-boundary defects unexpectedly passed"
  assert_contains "$out" "SC1007" "representative dispatcher defect was hidden"
  assert_contains "$out" "SC2086" "representative canonical adapter defect was hidden"
  assert_contains "$out" "SC2164" "representative production-owner defect was hidden"
  assert_contains "$out" "SC2155" "representative test-local defect was hidden"
  assert_not_contains "$out" "SC2154" "the production owner lost source-aware dependency context"
  [ "$(printf '%s\n' "$out" | grep -Fc 'SC2086 (info)')" -eq 1 ] \
    || fail "the dispatcher boundary re-imported the adapter diagnostic"
  [ "$(printf '%s\n' "$out" | grep -Fc 'SC2164 (warning)')" -eq 1 ] \
    || fail "the test boundary re-imported the production-owner diagnostic"
  pass "seeded dispatcher, adapter, production-owner, and test-local diagnostics preserve parity"
}

test_help_reports_the_complete_interface
test_list_files_reports_the_shell_inventory
test_fast_mode_disables_extended_analysis
test_ci_defaults_to_full_analysis
test_ci_rejects_explicit_fast_mode
test_fast_mode_catches_a_real_lint_defect
test_pins_an_explicit_version
test_installer_retries_transient_download_failure
test_installer_selects_platform_archive_url_and_checksum
test_installer_rejects_wrong_checksum
test_installer_falls_back_to_shasum
test_installer_prefers_sha256sum_over_shasum
test_installer_rejects_unsupported_platform
test_missing_shellcheck_fails_closed
test_rejects_wrong_shellcheck_version
test_catches_a_real_lint_defect
test_rejects_direct_beads_cli_invocations
test_rejects_direct_beads_cli_in_explicit_core_path
test_ignores_ambient_shellcheck_opts
test_clean_fixture_passes
test_jobs_are_deterministic_and_complete
test_worker_trees_stop_on_signal
test_seeded_module_boundary_parity
test_changed_mode_lints_only_the_changed_file
test_ci_forces_full_lint_even_with_empty_diff
test_main_branch_forces_full_lint
test_explicit_path_bypasses_changed_logic
test_zero_changed_files_exits_clean
test_list_files_respects_changed_mode
test_changed_mode_drops_external_sources_and_excludes_cross_file_codes
test_changed_mode_invokes_shellcheck_once_per_root
test_ci_keeps_external_sources_without_local_exclusions
test_main_branch_keeps_external_sources
test_merge_base_less_keeps_external_sources
test_explicit_path_keeps_external_sources
test_fast_mode_on_a_local_branch_keeps_source_following
test_changed_mode_hides_cross_file_codes_that_ci_still_sees
test_local_exclusion_list_covers_every_no_external_sources_code
