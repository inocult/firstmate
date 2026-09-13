# shellcheck shell=bash
# Shared "supervision missing" predicate.
# Usage: . bin/xo-supervision-lib.sh
#
# Reports whether an xo home needs supervision (xo_supervision_status
# below is the single owner of that condition set), and whether its watcher has
# a fresh liveness beacon (state/.last-watcher-beat, touched every poll cycle,
# within the grace window).
# bin/xo-turnend-guard.sh uses the PID-strict xo_watcher_healthy from
# bin/xo-wake-lib.sh for its block decision. bin/xo-guard.sh uses the model-aware
# xo_watcher_supervision_verdict (also in bin/xo-wake-lib.sh), which owns what a
# live watcher process means per supervision model. The status fields here retain
# the beacon-age details used in their messages.

# Portable mtime; Linux stat lacks -f, macOS stat lacks -c.
xo_sup_stat_mtime() {
  if [ "$(uname)" = Darwin ]; then
    /usr/bin/stat -f %m "$1" 2>/dev/null
  else
    stat -c %Y "$1" 2>/dev/null
  fi
}

# xo_supervision_status <state-dir> [grace-seconds]
# Populates, for the state dir at $1:
#   XO_SUP_IN_FLIGHT      count of state/*.meta (in-flight tasks)
#   XO_SUP_SOURCES        count of registered process-to-event sources
#   XO_SUP_CHECKS         count of registered custom checks: a state/<id>.check.sh
#                         with the state/<id>.check-trust binding that
#                         bin/xo-check-register.sh writes. Task PR polls carry no
#                         such binding and are torn down with their task, and the
#                         relay shim keeps its own trust path, so neither counts
#                         here. Presence of the binding is the whole test: whether
#                         those bytes are still the registered ones is the check
#                         sweep's call at execution time, and a home whose check
#                         no longer validates needs the watcher precisely so the
#                         sweep can report the rejection instead of going quiet.
#   XO_SUP_NEEDED         true/false - in-flight work, an X-mode relay poll, a
#                         registered event source (a source is a wait on an
#                         external process, not a task, so it has no metadata),
#                         or a registered custom check
#   XO_SUP_WATCHER_FRESH  true/false - a watcher beacon within the grace window
#   XO_SUP_BEACON_DESC    human-readable beacon age, for banners ("never" if absent)
#   XO_SUP_QUEUE_PENDING  true/false - state/.wake-queue has unread records
# grace-seconds defaults to $XO_GUARD_GRACE, then 300, matching xo-guard.sh.
# Always returns 0; callers read the vars, or use xo_supervision_unhealthy below.
xo_supervision_status() {
  local state=$1 grace=${2:-${XO_GUARD_GRACE:-300}} meta source check id beat m age
  XO_SUP_IN_FLIGHT=0
  XO_SUP_NEEDED=false
  XO_SUP_WATCHER_FRESH=false
  XO_SUP_BEACON_DESC=never
  XO_SUP_QUEUE_PENDING=false

  for meta in "$state"/*.meta; do
    [ -e "$meta" ] || continue
    XO_SUP_IN_FLIGHT=$((XO_SUP_IN_FLIGHT + 1))
  done
  XO_SUP_SOURCES=0
  for source in "$state"/procevent/*.source; do
    [ -e "$source" ] || continue
    XO_SUP_SOURCES=$((XO_SUP_SOURCES + 1))
  done
  XO_SUP_CHECKS=0
  for check in "$state"/*.check.sh; do
    [ -e "$check" ] || continue
    id=${check##*/}
    id=${id%.check.sh}
    if [ "$id" = x-watch ]; then
      continue
    fi
    [ -e "$state/$id.check-trust" ] || continue
    XO_SUP_CHECKS=$((XO_SUP_CHECKS + 1))
  done
  if [ "$XO_SUP_IN_FLIGHT" -gt 0 ] \
    || [ -f "$state/x-watch.check.sh" ] \
    || [ "$XO_SUP_SOURCES" -gt 0 ] \
    || [ "$XO_SUP_CHECKS" -gt 0 ]; then
    XO_SUP_NEEDED=true
  fi

  beat="$state/.last-watcher-beat"
  if [ -e "$beat" ]; then
    m=$(xo_sup_stat_mtime "$beat")
    if [ -n "$m" ]; then
      age=$(( $(date +%s) - m ))
      XO_SUP_BEACON_DESC="${age}s ago"
      [ "$age" -lt "$grace" ] && XO_SUP_WATCHER_FRESH=true
    else
      # shellcheck disable=SC2034 # Read by callers (xo-guard.sh) after sourcing.
      XO_SUP_BEACON_DESC=unknown
    fi
  fi

  # shellcheck disable=SC2034 # Read by callers (xo-guard.sh) after sourcing.
  [ -s "$state/.wake-queue" ] && XO_SUP_QUEUE_PENDING=true
  return 0
}

# xo_supervision_needed <state-dir> [grace-seconds]
# Exit 0 (true) exactly when the home needs a watcher.
xo_supervision_needed() {
  xo_supervision_status "$@"
  [ "$XO_SUP_NEEDED" = true ]
}

# xo_supervision_unhealthy <state-dir> [grace-seconds]
# Exit 0 (true) exactly when supervision is needed and no watcher has a fresh
# beacon. Exit 1 (false) otherwise.
xo_supervision_unhealthy() {
  xo_supervision_status "$@"
  [ "$XO_SUP_NEEDED" = true ] && [ "$XO_SUP_WATCHER_FRESH" = false ]
}
