#!/usr/bin/env bash
# tests/xo-skills-installer-live-e2e.test.sh - live drift guard proving the
# real skills.sh installer still resolves `--skill stow` to the portable variant
# in skills/fieldcraft/stow rather than the same-named internal skill in
# skills/orders/stow, and that discovery lists only the portable skill.
#
# Why this file exists: the installer keys on the frontmatter name across
# every category, ignores metadata.internal in install mode, and keeps the
# first same-named hit of a sorted directory walk, so the portable variant wins
# only because `fieldcraft` sorts before `orders`. docs/configuration.md
# "Operational home layout and state" owns that fact and
# tests/xo-skills-tree.test.sh pins the ordering portably; this guard runs the
# real installer so a change in its resolution rule fails loudly instead of
# silently shipping the internal skill to third parties who ask for stow.
#
# The guard spends no model tokens but is opt-in because it executes the
# installer against this checkout. It never downloads anything: it requires a
# locally resolvable skills CLI (`npx --no-install skills --version`) and
# reports a capability skip otherwise.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

xo_live_gate opt-in XO_SKILLS_INSTALLER_LIVE npx

pass() { printf 'ok - %s\n' "$1"; }
note() { printf '# %s\n' "$1"; }

LAB=''
cleanup() { [ -z "$LAB" ] || rm -rf "$LAB"; }
fail() { printf 'not ok - %s\n' "$1" >&2; cleanup; exit 1; }
trap cleanup EXIT

frontmatter_name() {
  sed -n '2,/^---$/p' "$1" | sed -n 's/^name:[[:space:]]*//p' | head -n 1
}

# --no-install is the whole point: a host without the CLI in its local npm
# cache or node_modules skips instead of fetching a package inside a test.
VERSION=$(npx --no-install skills --version 2>/dev/null | tr -d '[:space:]') || VERSION=''
if [ -z "$VERSION" ]; then
  printf 'skip: live: skills CLI absent (npx --no-install skills --version failed; this guard never downloads it)\n'
  exit 0
fi
note "skills CLI $VERSION"

PUBLIC="$ROOT/skills/fieldcraft/stow/SKILL.md"
INTERNAL="$ROOT/skills/orders/stow/SKILL.md"
[ -f "$PUBLIC" ] || fail "public stow skill missing at skills/fieldcraft/stow/SKILL.md"
[ -f "$INTERNAL" ] || fail "internal stow skill missing at skills/orders/stow/SKILL.md"
[ "$(frontmatter_name "$PUBLIC")" = stow ] || fail "skills/fieldcraft/stow/SKILL.md must declare frontmatter name stow"
[ "$(frontmatter_name "$INTERNAL")" = stow ] || fail "skills/orders/stow/SKILL.md must declare frontmatter name stow"

LAB=$(mktemp -d "${TMPDIR:-/tmp}/xo-skills-installer-live.XXXXXX") || fail "cannot create the guard lab"
LAB=$(cd -P -- "$LAB" && pwd -P)
mkdir -p "$LAB/install" "$LAB/list"

# Install mode: --skill stow must resolve to the portable variant even though
# the internal one shares its name and install mode ignores metadata.internal.
(cd "$LAB/install" && npx --no-install skills add "$ROOT" --skill stow -a claude-code -y >"$LAB/install.log" 2>&1) \
  || fail "skills add --skill stow failed: $(cat "$LAB/install.log")"
INSTALLED=$(find "$LAB/install" -name SKILL.md -type f)
[ "$(printf '%s\n' "$INSTALLED" | grep -c .)" -eq 1 ] \
  || fail "expected exactly one installed SKILL.md, got: ${INSTALLED:-none}; log: $(cat "$LAB/install.log")"
[ "$(basename "$(dirname "$INSTALLED")")" = stow ] || fail "installed skill directory is not named stow: $INSTALLED"
[ "$(frontmatter_name "$INSTALLED")" = stow ] || fail "installed SKILL.md does not declare frontmatter name stow"
if sed -n '2,/^---$/p' "$INSTALLED" | grep -Eq '^[[:space:]]*internal:[[:space:]]*true[[:space:]]*$'; then
  fail "--skill stow installed the internal variant (metadata.internal is set)"
fi
cmp -s "$INSTALLED" "$PUBLIC" \
  || fail "--skill stow installed a file that differs from skills/fieldcraft/stow/SKILL.md ($(wc -l <"$INSTALLED") lines installed, $(wc -l <"$PUBLIC") in the public variant)"
pass "--skill stow installs the public variant ($(wc -l <"$PUBLIC") lines, frontmatter name stow, no metadata.internal)"

# Discovery: without --skill the installer honours metadata.internal, so it
# must find exactly the one public skill and install nothing else.
(cd "$LAB/list" && npx --no-install skills add "$ROOT" -a claude-code -y >"$LAB/list.log" 2>&1) \
  || fail "skills add discovery run failed: $(cat "$LAB/list.log")"
grep -q 'Found 1 skill' "$LAB/list.log" \
  || fail "discovery did not report exactly one skill: $(grep -E 'Found [0-9]+ skill' "$LAB/list.log" || cat "$LAB/list.log")"
LISTED=$(find "$LAB/list" -name SKILL.md -type f)
[ "$(printf '%s\n' "$LISTED" | grep -c .)" -eq 1 ] \
  || fail "discovery installed more than the one public skill: ${LISTED:-none}"
[ "$(basename "$(dirname "$LISTED")")" = stow ] || fail "discovery installed a skill other than stow: $LISTED"
pass "discovery without --skill finds and installs exactly the one public skill"
