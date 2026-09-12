#!/usr/bin/env bash
# Structural regression for the skills tree. skills/<category>/<name>/SKILL.md
# is the single source for every bundled skill and .agents/skills/<name> is a
# committed relative activation link into it, so which skills a home loads is
# expressed by which links exist. docs/configuration.md "Operational home
# layout and state" owns the layout and the category scheme pinned here.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CATEGORIES="deprecated in-progress engineering operations misc"

category_known() {
  case " $CATEGORIES " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

frontmatter_name() {
  sed -n '2,/^---$/p' "$1" | sed -n 's/^name:[[:space:]]*//p' | head -n 1
}

# Audience is the metadata.internal marker, not the category a skill lives in.
is_internal() {
  sed -n '2,/^---$/p' "$1" | grep -Eq '^[[:space:]]*internal:[[:space:]]*true[[:space:]]*$'
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

test_every_canonical_skill_lives_in_a_known_category_as_at_most_two_audience_variants() {
  # A directory name may repeat across categories only as audience variants:
  # one portable (no metadata.internal marker) and one internal.
  local skill category name audience seen="" count=0
  for skill in "$ROOT"/skills/*/*/SKILL.md; do
    [ -f "$skill" ] || fail "no canonical skills found under skills/<category>/<name>/"
    category=$(basename "$(dirname "$(dirname "$skill")")")
    name=$(basename "$(dirname "$skill")")
    category_known "$category" || fail "skills/$category/$name is in an unknown category"
    if is_internal "$skill"; then audience=internal; else audience=portable; fi
    case " $seen " in
      *" $name=$audience "*) fail "skill $name has two $audience variants; a name may repeat across categories only as one portable and one internal audience variant" ;;
    esac
    seen="$seen $name=$audience"
    count=$((count + 1))
  done
  for skill in "$ROOT"/skills/*/SKILL.md; do
    [ ! -e "$skill" ] || fail "uncategorized skill at skills/$(basename "$(dirname "$skill")")"
  done
  pass "every canonical skill lives in a known category, repeating a name only as one portable and one internal audience variant ($count skills)"
}

test_portable_variant_is_the_first_installer_hit_of_every_shared_name() {
  # skills.sh installers resolve --skill <name> by frontmatter name across
  # every category, ignore metadata.internal in install mode, and keep the
  # first same-named hit of a sorted directory walk, so the portable variant
  # of a shared name is what third parties receive only because its directory
  # sorts first (misc before operations for stow). docs/configuration.md
  # "Operational home layout and state" owns the fact;
  # tests/fm-skills-installer-live-e2e.test.sh proves it live.
  local name candidate first portable internal hits shared=0
  for name in $(cd "$ROOT" && for skill in skills/*/*/SKILL.md; do frontmatter_name "$skill"; done | LC_ALL=C sort -u); do
    first='' portable='' internal='' hits=0
    while IFS= read -r candidate; do
      [ "$(frontmatter_name "$ROOT/$candidate")" = "$name" ] || continue
      hits=$((hits + 1))
      [ -n "$first" ] || first=$candidate
      if is_internal "$ROOT/$candidate"; then
        [ -z "$internal" ] || fail "frontmatter name $name is internal in both $internal and $candidate; at most one variant per name may be internal"
        internal=$candidate
      else
        [ -z "$portable" ] || fail "frontmatter name $name is portable in both $portable and $candidate; at most one variant per name may be portable"
        portable=$candidate
      fi
    done < <(cd "$ROOT" && printf '%s\n' skills/*/*/SKILL.md | LC_ALL=C sort)
    [ "$hits" -gt 1 ] || continue
    shared=$((shared + 1))
    [ -n "$portable" ] || fail "frontmatter name $name exists in more than one category with no portable variant"
    [ "$first" = "$portable" ] \
      || fail "$portable is not the first $name hit of a C-sorted walk of skills/*/*/SKILL.md (first hit: $first), so --skill $name would install the internal variant"
  done
  [ "$shared" -gt 0 ] \
    || fail "expected at least one frontmatter name shared across categories (the two stow variants); update this test if that pairing was removed deliberately"
  pass "the portable variant is the first C-sorted installer hit for every shared skill name ($shared shared)"
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
test_every_canonical_skill_lives_in_a_known_category_as_at_most_two_audience_variants
test_portable_variant_is_the_first_installer_hit_of_every_shared_name
test_claude_alias_reaches_every_active_skill
