# shellcheck shell=bash disable=SC2034
# xo-secondmate-restart-lib.sh - the shared contract for restarting a second
# mate onto the current instruction surface and launch-time wiring. Source only.
#
# Two consumers, one owner:
#   - bin/xo-update.sh decides WHICH live mates belong in the restart set, so it
#     needs the capability test before it prints its action lines.
#   - bin/xo-secondmate-restart.sh performs the pass, so it needs the same test
#     again on its own argv rather than trusting a caller's list.
#
# The capability test is the pre-stop half of the control plane's own refusals
# (bin/xo-control-lib.sh owns those tables): a mate whose recorded backend has
# no recovery-grade agent-state classifier, or whose harness has no verified
# control mechanics, can never have "the old agent stopped and the replacement
# came up" proven for it. Asking here keeps that verdict on the side of the
# transaction where nothing has been touched yet, so an incapable mate is routed
# to the ordinary re-read nudge instead of being stopped for a launch that must
# be refused.
#
# Placement is resolved from the same remote_host= signal bin/xo-send.sh routes
# on, and it changes only the transport: the restart itself is bin/xo-control.sh
# <id> relaunch either way, run here for a local mate and run on the host over
# bin/xo-on.sh for a remote one.

_XO_SECONDMATE_RESTART_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/xo-backend.sh disable=SC1091
. "$_XO_SECONDMATE_RESTART_LIB_DIR/xo-backend.sh"
# shellcheck source=bin/xo-control-lib.sh disable=SC1091
. "$_XO_SECONDMATE_RESTART_LIB_DIR/xo-control-lib.sh"

# The persist request the primary sends before it restarts anything. It is the
# open-record half of /stow and nothing more: a restart needs the state of work
# written down, not a memory curation pass, and bundling one would make every
# instruction update cost far more than the reload it is paying for.
# The mate answers through its parent channel, which is what resolves the
# parent-owned reply expectation xo-send arms for a marked request; that
# correlated answer, never the wall clock, is what releases the restart.
XO_SECONDMATE_PERSIST_REQUEST='XO was updated and I am about to restart your agent so it comes up on the current instructions and launch-time settings, which drops your conversation but keeps every durable record. Before that, persist the open work you are holding only in this conversation, following the /stow skill'"'"'s "Open-record persistence" section and nothing else from that skill: file a task for each open record that exists only in this conversation, including any captain call you had formed but never registered, and correct any task whose status no longer reflects what you now know. Do NOT run the memory, learnings, or captain-preference sweeps. Then reply on your parent channel saying it is done, or saying what you deliberately left alone and why.'

# Resolve one mate's restart capability from its durable record alone.
# Publishes, on success:
#   XO_SECONDMATE_RESTART_PLACEMENT  local|remote
#   XO_SECONDMATE_RESTART_BACKEND    the backend whose classifier must prove the stop
#   XO_SECONDMATE_RESTART_HARNESS    the verified control adapter it runs on
#   XO_SECONDMATE_RESTART_HOST       the configured host (remote placement only)
# and on failure sets XO_SECONDMATE_RESTART_REASON to one operator-readable line.
XO_SECONDMATE_RESTART_PLACEMENT=""
XO_SECONDMATE_RESTART_BACKEND=""
XO_SECONDMATE_RESTART_HARNESS=""
XO_SECONDMATE_RESTART_HOST=""
XO_SECONDMATE_RESTART_REASON=""
xo_secondmate_restart_capable() {  # <meta-file>
  local meta=$1 kind window remote_host backend harness family
  XO_SECONDMATE_RESTART_PLACEMENT=""
  XO_SECONDMATE_RESTART_BACKEND=""
  XO_SECONDMATE_RESTART_HARNESS=""
  XO_SECONDMATE_RESTART_HOST=""
  XO_SECONDMATE_RESTART_REASON=""

  if [ ! -f "$meta" ] || [ -L "$meta" ]; then
    XO_SECONDMATE_RESTART_REASON="no durable record for this second mate in this home"
    return 1
  fi
  kind=$(xo_meta_get "$meta" kind)
  if [ "$kind" != secondmate ]; then
    XO_SECONDMATE_RESTART_REASON="the durable record is not a second mate's"
    return 1
  fi
  window=$(xo_meta_get "$meta" window)
  if [ -z "$window" ]; then
    XO_SECONDMATE_RESTART_REASON="the durable record names no endpoint, so there is no agent to replace"
    return 1
  fi
  harness=$(xo_meta_get "$meta" harness)
  remote_host=$(xo_meta_get "$meta" remote_host)
  if [ -n "$remote_host" ]; then
    XO_SECONDMATE_RESTART_PLACEMENT=remote
    XO_SECONDMATE_RESTART_HOST=$remote_host
    # A remote mate's endpoint record lives on its host; the parent's own record
    # names the backend that launch established there, and the remote route
    # accepts nothing but herdr.
    backend=$(xo_meta_get "$meta" remote_backend)
    [ -n "$backend" ] || backend=herdr
  else
    XO_SECONDMATE_RESTART_PLACEMENT=local
    backend=$(xo_backend_of_meta "$meta")
  fi
  XO_SECONDMATE_RESTART_BACKEND=$backend
  if ! xo_control_backend_state_verified "$backend"; then
    XO_SECONDMATE_RESTART_REASON="its runtime cannot prove an agent stopped and came back (backend $backend)"
    return 1
  fi
  if ! family=$(xo_control_harness_family "$harness") \
    || ! xo_control_harness_supported "$family" \
    || ! xo_control_harness_supports_kind "$family" secondmate; then
    XO_SECONDMATE_RESTART_REASON="its worker runtime '${harness:-none}' has no verified restart mechanics for a second mate"
    return 1
  fi
  XO_SECONDMATE_RESTART_HARNESS=$family
  return 0
}
