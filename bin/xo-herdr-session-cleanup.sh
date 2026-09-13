#!/usr/bin/env bash
# Retire stale restored-shell Herdr presentation children at locked session start.
#
# Usage: xo-herdr-session-cleanup.sh
#
# The caller must already own this XO home's session lock. This script is
# home-local and considers only the current named Herdr session and ordinary
# state/*.herdr-presentation journals in the effective XO_HOME. Each candidate
# is additionally serialized by the existing state/.spawn-<task>.lock and the
# shared named-session Herdr presentation lock, in that order.
#
# A visible title is discovery only. Cleanup requires the exact current
# "└ <concise-task> · p:<22-char-token>" grammar, one token occurrence across
# the named-session snapshot, exactly one matching home-local journal, one tab,
# one pane, absent task metadata, no registered agent, and a process proof that
# the pane contains only one idle recognized shell with no child process. A
# version 2 journal must also bind the exact workspace, tab, and pane.
# Topology is first checked from one locked API snapshot, then every mutation
# prerequisite is immediately rechecked before the existing exact-pane
# focus-preserving close helper is called.
# The script never closes a workspace. It removes only the matching journal,
# and only after the exact pane is confirmed gone. Every error warns and returns
# success so session startup continues conservatively.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XO_ROOT="${XO_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
XO_HOME="${XO_HOME:-${XO_ROOT_OVERRIDE:-$XO_ROOT}}"
STATE="${XO_STATE_OVERRIDE:-$XO_HOME/state}"

# shellcheck source=bin/xo-wake-lib.sh
. "$SCRIPT_DIR/xo-wake-lib.sh"
# shellcheck source=bin/xo-backend.sh
. "$SCRIPT_DIR/xo-backend.sh"
xo_backend_source herdr
# shellcheck source=bin/xo-pr-lib.sh
. "$SCRIPT_DIR/xo-pr-lib.sh"

xo_herdr_cleanup_warn() {
  printf 'warning: herdr session-start projection cleanup: %s\n' "$*" >&2
}

xo_herdr_cleanup_title_token() { # <workspace-title>
  local title=$1 prefix token rest
  case "$title" in
    '└ '*' · p:'*) ;;
    *) return 1 ;;
  esac
  token=${title##*' · p:'}
  prefix=${title%" · p:$token"}
  [ "$prefix" != "$title" ] && [ -n "${prefix#'└ '}" ] || return 1
  [ "${#token}" -eq 22 ] || return 1
  case "$token" in *[!A-Za-z0-9_-]*) return 1 ;; esac
  rest=${title#*p:}
  [ "$rest" != "$title" ] || return 1
  case "$rest" in *p:*) return 1 ;; esac
  printf '%s' "$token"
}

xo_herdr_cleanup_home_identity() {
  [ -d "$XO_HOME" ] && [ ! -L "$XO_HOME" ] || return 1
  (cd "$XO_HOME" 2>/dev/null && pwd -P)
}

xo_herdr_cleanup_journal_matches() { # <title> <session> <home-real>
  local title=$1 session=$2 home_real=$3 journal id expected journal_home
  [ -d "$STATE" ] && [ ! -L "$STATE" ] || return 1
  for journal in "$STATE"/*"$XO_BACKEND_HERDR_PRESENTATION_JOURNAL_SUFFIX"; do
    [ -f "$journal" ] && [ ! -L "$journal" ] || continue
    id=$(basename "$journal" "$XO_BACKEND_HERDR_PRESENTATION_JOURNAL_SUFFIX")
    xo_task_id_creation_valid "$id" || continue
    xo_backend_herdr_projection_journal_snapshot "$journal" "$id" || continue
    if [ "$XO_BACKEND_HERDR_JOURNAL_VERSION" = 2 ]; then
      journal_home=$(xo_backend_herdr_projection_home_identity \
        "$XO_BACKEND_HERDR_JOURNAL_HOME" 2>/dev/null) || continue
      [ "$journal_home" = "$home_real" ] \
        && [ "$XO_BACKEND_HERDR_JOURNAL_SESSION" = "$session" ] || continue
    fi
    expected=$(xo_backend_herdr_projection_workspace_label \
      "$id" "$XO_BACKEND_HERDR_JOURNAL_PROJECTION_ID")
    [ "$expected" = "$title" ] || continue
    printf '%s\t%s\t%s\n' "$journal" "$id" "$XO_BACKEND_HERDR_JOURNAL_PROJECTION_ID"
  done
}

xo_herdr_cleanup_unique_match() { # <title> <session> <home-real>
  local title=$1 session=$2 home_real=$3 matches count record
  XO_HERDR_CLEANUP_JOURNAL=
  XO_HERDR_CLEANUP_ID=
  XO_HERDR_CLEANUP_TOKEN=
  XO_HERDR_CLEANUP_VERSION=
  XO_HERDR_CLEANUP_BOUND_WORKSPACE=
  XO_HERDR_CLEANUP_BOUND_TAB=
  XO_HERDR_CLEANUP_BOUND_PANE=
  matches=$(xo_herdr_cleanup_journal_matches "$title" "$session" "$home_real") || return 1
  count=$(printf '%s\n' "$matches" | awk 'NF { n++ } END { print n+0 }')
  [ "$count" -eq 1 ] || return 1
  record=$(printf '%s\n' "$matches" | awk 'NF { print; exit }')
  XO_HERDR_CLEANUP_JOURNAL=${record%%$'\t'*}
  record=${record#*$'\t'}
  XO_HERDR_CLEANUP_ID=${record%%$'\t'*}
  XO_HERDR_CLEANUP_TOKEN=${record#*$'\t'}
  [ -n "$XO_HERDR_CLEANUP_JOURNAL" ] \
    && [ -n "$XO_HERDR_CLEANUP_ID" ] \
    && [ -n "$XO_HERDR_CLEANUP_TOKEN" ] || return 1
  xo_backend_herdr_projection_journal_snapshot \
    "$XO_HERDR_CLEANUP_JOURNAL" "$XO_HERDR_CLEANUP_ID" || return 1
  [ "$XO_BACKEND_HERDR_JOURNAL_PROJECTION_ID" = "$XO_HERDR_CLEANUP_TOKEN" ] || return 1
  XO_HERDR_CLEANUP_VERSION=$XO_BACKEND_HERDR_JOURNAL_VERSION
  if [ "$XO_HERDR_CLEANUP_VERSION" = 2 ]; then
    XO_HERDR_CLEANUP_BOUND_WORKSPACE=$XO_BACKEND_HERDR_JOURNAL_WORKSPACE_ID
    XO_HERDR_CLEANUP_BOUND_TAB=$XO_BACKEND_HERDR_JOURNAL_TAB_ID
    XO_HERDR_CLEANUP_BOUND_PANE=$XO_BACKEND_HERDR_JOURNAL_PANE_ID
  fi
}

xo_herdr_cleanup_snapshot_candidate() { # <snapshot> <workspace> <title> <token> <bound-workspace> <bound-tab> <bound-pane>
  local snapshot=$1 workspace=$2 title=$3 token=$4
  local bound_workspace=$5 bound_tab=$6 bound_pane=$7 record
  XO_HERDR_CLEANUP_TAB=
  XO_HERDR_CLEANUP_PANE=
  record=$(printf '%s' "$snapshot" | jq -er \
    --arg workspace "$workspace" --arg title "$title" --arg token "$token" \
    --arg bound_workspace "$bound_workspace" --arg bound_tab "$bound_tab" \
    --arg bound_pane "$bound_pane" '
    .result.snapshot as $s
    | [$s.workspaces[]? | select(.workspace_id == $workspace)] as $workspaces
    | [$s.tabs[]? | select(.workspace_id == $workspace)] as $tabs
    | [$s.panes[]? | select(.workspace_id == $workspace)] as $panes
    | ([ $s.workspaces[]?.label? // "" |
         ((split("p:" + $token) | length) - 1) ] | add // 0) as $token_count
    | select($workspaces | length == 1)
    | select($workspaces[0].label == $title)
    | select($workspaces[0].tab_count == 1 and $workspaces[0].pane_count == 1)
    | select($tabs | length == 1)
    | select($panes | length == 1)
    | select($panes[0].tab_id == $tabs[0].tab_id)
    | select($bound_workspace == "" or $workspace == $bound_workspace)
    | select($bound_tab == "" or $tabs[0].tab_id == $bound_tab)
    | select($bound_pane == "" or $panes[0].pane_id == $bound_pane)
    | select($token_count == 1)
    | select(($s.focused_workspace_id | type) == "string")
    | select(($s.focused_tab_id | type) == "string")
    | select(($s.focused_pane_id | type) == "string")
    | select($s.focused_tab_id != $tabs[0].tab_id)
    | [$tabs[0].tab_id, $panes[0].pane_id] | @tsv
  ' 2>/dev/null) || return 1
  [ -n "$record" ] && [ "${record#*$'\t'}" != "$record" ] || return 1
  XO_HERDR_CLEANUP_TAB=${record%%$'\t'*}
  XO_HERDR_CLEANUP_PANE=${record#*$'\t'}
  [ -n "$XO_HERDR_CLEANUP_TAB" ] && [ -n "$XO_HERDR_CLEANUP_PANE" ]
}

xo_herdr_cleanup_revalidate() { # <session> <workspace> <tab> <pane> <title> <token> <home-real> <journal> <task-id> <version> <bound-workspace> <bound-tab> <bound-pane>
  local session=$1 workspace=$2 tab=$3 pane=$4 title=$5 token=$6 home_real=$7
  local journal=$8 id=$9 version=${10} bound_workspace=${11} bound_tab=${12} bound_pane=${13}
  local workspaces workspace_info tabs panes focus
  [ ! -e "$STATE/$id.meta" ] && [ ! -L "$STATE/$id.meta" ] || return 1
  xo_herdr_cleanup_unique_match "$title" "$session" "$home_real" || return 1
  [ "$XO_HERDR_CLEANUP_JOURNAL" = "$journal" ] \
    && [ "$XO_HERDR_CLEANUP_ID" = "$id" ] \
    && [ "$XO_HERDR_CLEANUP_TOKEN" = "$token" ] \
    && [ "$XO_HERDR_CLEANUP_VERSION" = "$version" ] \
    && [ "$XO_HERDR_CLEANUP_BOUND_WORKSPACE" = "$bound_workspace" ] \
    && [ "$XO_HERDR_CLEANUP_BOUND_TAB" = "$bound_tab" ] \
    && [ "$XO_HERDR_CLEANUP_BOUND_PANE" = "$bound_pane" ] || return 1

  workspaces=$(xo_backend_herdr_cli "$session" workspace list 2>/dev/null) || return 1
  printf '%s' "$workspaces" | jq -e --arg workspace "$workspace" --arg title "$title" --arg token "$token" '
    ([.result.workspaces[]? | select(.workspace_id == $workspace and .label == $title)] | length) == 1
    and ([.result.workspaces[]?.label? // "" |
          ((split("p:" + $token) | length) - 1)] | add // 0) == 1
  ' >/dev/null 2>&1 || return 1
  workspace_info=$(xo_backend_herdr_cli "$session" workspace get "$workspace" 2>/dev/null) || return 1
  printf '%s' "$workspace_info" | jq -e --arg workspace "$workspace" --arg title "$title" '
    .result.workspace.workspace_id == $workspace
    and .result.workspace.label == $title
    and .result.workspace.tab_count == 1
    and .result.workspace.pane_count == 1
  ' >/dev/null 2>&1 || return 1
  tabs=$(xo_backend_herdr_cli "$session" tab list --workspace "$workspace" 2>/dev/null) || return 1
  printf '%s' "$tabs" | jq -e --arg workspace "$workspace" --arg tab "$tab" '
    (.result.tabs | type) == "array"
    and (.result.tabs | length) == 1
    and .result.tabs[0].workspace_id == $workspace
    and .result.tabs[0].tab_id == $tab
  ' >/dev/null 2>&1 || return 1
  panes=$(xo_backend_herdr_cli "$session" pane list --workspace "$workspace" 2>/dev/null) || return 1
  printf '%s' "$panes" | jq -e --arg workspace "$workspace" --arg tab "$tab" --arg pane "$pane" '
    (.result.panes | type) == "array"
    and (.result.panes | length) == 1
    and .result.panes[0].workspace_id == $workspace
    and .result.panes[0].tab_id == $tab
    and .result.panes[0].pane_id == $pane
  ' >/dev/null 2>&1 || return 1
  [ "$(xo_backend_herdr_pane_agent_state "$session" "$pane")" = no-agent ] || return 1
  xo_backend_herdr_pane_idle_shell_pid "$session" "$pane" >/dev/null || return 1
  focus=$(xo_backend_herdr_projection_focus_snapshot "$session") || return 1
  [ "${focus#*$'\t'}" != "$tab" ]
}

xo_herdr_cleanup_one() { # <session> <workspace> <title> <home-real>
  local session=$1 workspace=$2 title=$3 home_real=$4 token journal id task_lock
  local version bound_workspace bound_tab bound_pane presentation_lock snapshot
  local tab pane state close_status=0
  token=$(xo_herdr_cleanup_title_token "$title") || return 0
  if ! xo_herdr_cleanup_unique_match "$title" "$session" "$home_real"; then
    return 0
  fi
  journal=$XO_HERDR_CLEANUP_JOURNAL
  id=$XO_HERDR_CLEANUP_ID
  version=$XO_HERDR_CLEANUP_VERSION
  bound_workspace=$XO_HERDR_CLEANUP_BOUND_WORKSPACE
  bound_tab=$XO_HERDR_CLEANUP_BOUND_TAB
  bound_pane=$XO_HERDR_CLEANUP_BOUND_PANE
  [ "$XO_HERDR_CLEANUP_TOKEN" = "$token" ] || return 0
  task_lock="$STATE/.spawn-$id.lock"
  if ! xo_lock_try_acquire "$task_lock"; then
    xo_herdr_cleanup_warn "$id skipped because its task lock is busy"
    return 0
  fi
  presentation_lock=$(xo_backend_herdr_presentation_session_lock_path "$session" 2>/dev/null) || {
    xo_lock_release "$task_lock" || true
    xo_herdr_cleanup_warn "$id skipped because the shared presentation lock is unavailable"
    return 0
  }
  if ! xo_lock_try_acquire "$presentation_lock"; then
    xo_lock_release "$task_lock" || true
    xo_herdr_cleanup_warn "$id skipped because the shared presentation lock is busy"
    return 0
  fi

  if [ -e "$STATE/$id.meta" ] || [ -L "$STATE/$id.meta" ]; then
    xo_lock_release "$presentation_lock" || true
    xo_lock_release "$task_lock" || true
    return 0
  fi
  snapshot=$(xo_backend_herdr_cli "$session" api snapshot 2>/dev/null) || snapshot=
  if [ -z "$snapshot" ] \
    || ! xo_herdr_cleanup_snapshot_candidate \
      "$snapshot" "$workspace" "$title" "$token" \
      "$bound_workspace" "$bound_tab" "$bound_pane"; then
    xo_herdr_cleanup_warn "$id preserved because its locked candidate snapshot was ambiguous"
    xo_lock_release "$presentation_lock" || true
    xo_lock_release "$task_lock" || true
    return 0
  fi
  tab=$XO_HERDR_CLEANUP_TAB
  pane=$XO_HERDR_CLEANUP_PANE
  if [ "$(xo_backend_herdr_pane_agent_state "$session" "$pane")" != no-agent ] \
    || ! xo_backend_herdr_pane_idle_shell_pid "$session" "$pane" >/dev/null; then
    xo_herdr_cleanup_warn "$id preserved because its pane is not a provably idle childless shell"
    xo_lock_release "$presentation_lock" || true
    xo_lock_release "$task_lock" || true
    return 0
  fi
  if ! xo_herdr_cleanup_revalidate \
    "$session" "$workspace" "$tab" "$pane" "$title" "$token" "$home_real" \
    "$journal" "$id" "$version" "$bound_workspace" "$bound_tab" "$bound_pane"; then
    xo_herdr_cleanup_warn "$id preserved because immediate revalidation changed or was unreadable"
    xo_lock_release "$presentation_lock" || true
    xo_lock_release "$task_lock" || true
    return 0
  fi

  # This unconditional retirement is the authorized containment documented
  # with the presentation floor ownership in bin/backends/herdr.sh.
  xo_backend_herdr_projection_close_pane_focus_preserving \
    "$session" "$pane" no-agent || close_status=$?
  state=$(xo_backend_herdr_pane_agent_state "$session" "$pane")
  if [ "$state" = dead ]; then
    if [ -f "$journal" ] && [ ! -L "$journal" ] \
      && xo_herdr_cleanup_unique_match "$title" "$session" "$home_real" \
      && [ "$XO_HERDR_CLEANUP_JOURNAL" = "$journal" ] \
      && [ "$XO_HERDR_CLEANUP_ID" = "$id" ] \
      && [ "$XO_HERDR_CLEANUP_VERSION" = "$version" ] \
      && [ "$XO_HERDR_CLEANUP_BOUND_WORKSPACE" = "$bound_workspace" ] \
      && [ "$XO_HERDR_CLEANUP_BOUND_TAB" = "$bound_tab" ] \
      && [ "$XO_HERDR_CLEANUP_BOUND_PANE" = "$bound_pane" ] \
      && [ ! -e "$STATE/$id.meta" ] && [ ! -L "$STATE/$id.meta" ]; then
      rm -f -- "$journal" || xo_herdr_cleanup_warn "$id pane closed but its journal could not be retired"
    else
      xo_herdr_cleanup_warn "$id pane closed but its journal changed and was preserved"
    fi
  elif [ "$close_status" -ne 0 ]; then
    xo_herdr_cleanup_warn "$id preserved because exact focus-safe pane closure was refused or unconfirmed"
  else
    xo_herdr_cleanup_warn "$id preserved because exact pane closure could not be confirmed"
  fi
  xo_lock_release "$presentation_lock" || true
  xo_lock_release "$task_lock" || true
  return 0
}

xo_herdr_session_cleanup() {
  local session home_real list candidates workspace title journal found=0
  [ -d "$STATE" ] && [ ! -L "$STATE" ] || return 0
  for journal in "$STATE"/*"$XO_BACKEND_HERDR_PRESENTATION_JOURNAL_SUFFIX"; do
    if [ -f "$journal" ] && [ ! -L "$journal" ]; then
      found=1
      break
    fi
  done
  [ "$found" -eq 1 ] || return 0
  command -v herdr >/dev/null 2>&1 \
    && command -v jq >/dev/null 2>&1 || return 0
  home_real=$(xo_herdr_cleanup_home_identity) || {
    xo_herdr_cleanup_warn 'home identity is unreadable; preserving every candidate'
    return 0
  }
  session=$(xo_backend_herdr_session)
  list=$(xo_backend_herdr_cli "$session" workspace list 2>/dev/null) || {
    xo_herdr_cleanup_warn "session '$session' workspace discovery failed; preserving every candidate"
    return 0
  }
  candidates=$(printf '%s' "$list" | jq -er '
    .result.workspaces
    | select(type == "array")
    | .[]
    | select((.workspace_id | type) == "string" and (.workspace_id | length) > 0)
    | select((.label | type) == "string" and (.label | length) > 0)
    | [.workspace_id, .label] | @tsv
  ' 2>/dev/null) || {
    xo_herdr_cleanup_warn "session '$session' workspace discovery was unreadable; preserving every candidate"
    return 0
  }
  while IFS=$'\t' read -r workspace title; do
    [ -n "$workspace" ] && [ -n "$title" ] || continue
    xo_herdr_cleanup_one "$session" "$workspace" "$title" "$home_real"
  done <<< "$candidates"
  return 0
}

if [ "${XO_HERDR_SESSION_CLEANUP_SOURCE_ONLY:-0}" != 1 ]; then
  xo_herdr_session_cleanup
  exit 0
fi
