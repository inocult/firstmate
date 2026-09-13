#!/usr/bin/env bash
# Shared durable, supervisor-facing outcome publication for a confirmed merge.
#
# Both a merge performed by this home and a merge detected by its existing poll
# use this operation, so neither outcome depends on an agent remembering it.
# This operation publishes the poll's local actionable row; the watcher
# immediately delivers that row as observation handling, not a second outcome
# path.
#
# The destination is the home's role, never the caller's choice:
#   - a secondmate home reports upward on its parent channel, resolved and
#     appended through bin/xo-parent-channel-lib.sh in the same
#     "<state> [key=<slug>]: <note>" shape the charter contract defines;
#   - a main home reports to the captain through the durable wake queue.
# A poll observed in a secondmate home also receives a local durable wake after
# the upward write, so the mate can handle its own poll observation.
# No new state file and no new transport are involved.
#
# Normal operation deduplicates the task's latest canonical PR identity through
# the merge-notification marker owned by bin/xo-pr-lib.sh. Main-home wake keys
# also include that PR identity so distinct PRs for a reused task remain
# distinct in queue presentation. The outcome is published before the marker
# is committed, so a failed commit stays eligible for at-least-once retry and
# may rarely duplicate rather than leave a merge silent.
#
# Sourced by bin/xo-pr-merge.sh, bin/xo-watch.sh, and tests. No side effects on
# source beyond its sourced libraries.

_XO_MERGE_OUTCOME_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/xo-pr-lib.sh
. "$_XO_MERGE_OUTCOME_LIB_DIR/xo-pr-lib.sh"
# shellcheck source=bin/xo-parent-channel-lib.sh
. "$_XO_MERGE_OUTCOME_LIB_DIR/xo-parent-channel-lib.sh"

# shellcheck disable=SC2034 # Public result consumed by sourcing callers.
XO_MERGE_OUTCOME_ALREADY_RECORDED=false

# xo_merge_outcome_report <home> <state> <task-id> <pr-url> <origin> [authority]
#
# <origin> says who observed the merge, because that decides whether the
# existing poll path also needs a local wake:
#   self - this home performed the merge.
#   poll - this home's merge poll detected the merge, so the canonical outcome
#          also wakes this home after any upward hop needed by a secondmate.
# Optional <authority> is yolo or away-grant when the merge ran while the
# away-posture record existed; it is appended to the ledger line. Known audit
# gap: queued merges and a poll that wins direct-merge deduplication publish an
# untagged row because the poll path does not persist merge authority.
#
# Returns 0 when the outcome is recorded (or already was), 2 on an invalid
# request, 3 when this home's own role or parent binding cannot be read well
# enough to say where the outcome belongs, and 1 on any other failure to
# record. A caller that has already merged must report a non-zero return rather
# than treat it as success: the merge landed and the record did not.
xo_merge_outcome_report() {  # <home> <state> <task-id> <pr-url> <origin> [authority]
  local home=$1 state=$2 id=$3 url=$4 origin=$5
  local authority=${6-} suffix=
  local self_rc=0 destination='' line lock status=0
  local provider host path number
  # shellcheck disable=SC2034 # Sourced wake helpers consume these scoped globals.
  local STATE XO_WAKE_QUEUE XO_WAKE_QUEUE_LOCK
  XO_MERGE_OUTCOME_ALREADY_RECORDED=false
  case "$origin" in self|poll) ;; *) return 2 ;; esac
  case "$authority" in
    yolo|away-grant) suffix=" $authority" ;;
    '') ;;
    *) return 2 ;;
  esac
  xo_pr_task_id_valid "$id" || return 2
  xo_pr_url_parse "$url" || return 2
  provider=$XO_PR_PROVIDER
  host=$XO_PR_HOST
  path=$XO_PR_PATH
  number=$XO_PR_NUMBER
  [ -d "$state" ] && [ ! -L "$state" ] || return 1

  if destination=$(xo_parent_channel_destination "$home" "$state"); then
    line="done [key=merged-$id]: merged $id $XO_PR_URL$suffix"
  else
    self_rc=$?
    [ "$self_rc" -eq 1 ] || return 3
    destination=''
  fi

  STATE=$state
  # shellcheck source=bin/xo-wake-lib.sh
  . "$_XO_MERGE_OUTCOME_LIB_DIR/xo-wake-lib.sh"
  lock="$state/$id.pr-poll-merge-notified.lock"
  xo_lock_acquire_wait "$lock" || return 1
  if xo_pr_poll_merge_already_notified "$state" "$id" \
    "$provider" "$host" "$path" "$number"; then
    # shellcheck disable=SC2034 # Public result consumed by sourcing callers.
    XO_MERGE_OUTCOME_ALREADY_RECORDED=true
    xo_lock_release "$lock"
    return 0
  fi

  if [ -n "$destination" ]; then
    xo_parent_channel_append_once "$destination" "$line" || status=1
  fi
  if [ "$status" -eq 0 ] && { [ "$origin" = poll ] || [ -z "$destination" ]; }; then
    xo_wake_append check "merged-$id-$XO_PR_URL" \
      "check: merge landed: $id $XO_PR_URL$suffix" || status=1
  fi
  if [ "$status" -eq 0 ]; then
    xo_pr_poll_merge_mark_notified "$state" "$id" \
      "$provider" "$host" "$path" "$number" || status=1
  fi
  xo_lock_release "$lock"
  return "$status"
}
