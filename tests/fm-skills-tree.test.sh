#!/usr/bin/env bash
# Structural regression for the skills tree. skills/<category>/<name>/SKILL.md
# is the single source for every bundled skill and .agents/skills/<name> is a
# committed relative activation link into it, so which skills a home loads is
# expressed by which links exist. docs/configuration.md "Operational home
# layout and state" owns the layout and the category scheme pinned here.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CATEGORIES="core missions experimental deprecated"

category_known() {
  case " $CATEGORIES " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

test_activation_links_are_committed_relative_links_into_the_tree() {
  local link name target rest category mode count=0
  for link in "$ROOT"/.agents/skills/*; do
    name=$(basename "$link")
    [ -L "$link" ] || fail ".agents/skills/$name is not an activation link into skills/"
    target=$(readlink "$link")
    rest=${target#../../skills/}
    [ "$rest" != "$target" ] || fail ".agents/skills/$name does not link relatively into skills/: $target"
    category=${rest%%/*}
    category_known "$category" || fail ".agents/skills/$name links into an unknown category: $target"
    [ "$rest" = "$category/$name" ] || fail ".agents/skills/$name links to a differently named skill: $target"
    [ -f "$link/SKILL.md" ] || fail ".agents/skills/$name resolves to no SKILL.md"
    mode=$(git -C "$ROOT" ls-files -s -- ".agents/skills/$name" | awk '{ print $1 }')
    [ "$mode" = 120000 ] || fail ".agents/skills/$name is not committed as a symlink (mode ${mode:-untracked})"
    count=$((count + 1))
  done
  [ "$count" -gt 0 ] || fail "no activation links found under .agents/skills"
  pass "every activation link is a committed relative symlink to a same-named skill in a known category ($count links)"
}

test_every_canonical_skill_lives_in_exactly_one_known_category() {
  local skill category name seen="" count=0
  for skill in "$ROOT"/skills/*/*/SKILL.md; do
    [ -f "$skill" ] || fail "no canonical skills found under skills/<category>/<name>/"
    category=$(basename "$(dirname "$(dirname "$skill")")")
    name=$(basename "$(dirname "$skill")")
    category_known "$category" || fail "skills/$category/$name is in an unknown category"
    case " $seen " in
      *" $name "*) fail "skill $name exists in more than one category" ;;
    esac
    seen="$seen $name"
    count=$((count + 1))
  done
  for skill in "$ROOT"/skills/*/SKILL.md; do
    [ ! -e "$skill" ] || fail "uncategorized skill at skills/$(basename "$(dirname "$skill")")"
  done
  pass "every canonical skill lives in exactly one known category ($count skills)"
}

test_claude_alias_reaches_every_active_skill() {
  local link name
  [ "$(readlink "$ROOT/.claude/skills")" = "../.agents/skills" ] \
    || fail ".claude/skills must stay a symlink to ../.agents/skills"
  for link in "$ROOT"/.agents/skills/*; do
    name=$(basename "$link")
    [ -f "$ROOT/.claude/skills/$name/SKILL.md" ] || fail ".claude/skills/$name does not reach its SKILL.md"
  done
  pass "the Claude skills alias reaches every active skill through the activation links"
}

test_activation_links_are_committed_relative_links_into_the_tree
test_every_canonical_skill_lives_in_exactly_one_known_category
test_claude_alias_reaches_every_active_skill
