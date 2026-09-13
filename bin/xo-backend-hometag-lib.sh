#!/usr/bin/env bash
# bin/xo-backend-hometag-lib.sh - shared per-installation home-tag derivation
# for session-provider backends whose container has ONE namespace shared by
# every xo home on the machine, with no native per-home split (cmux's
# one app-global workspace list, zellij's one shared "xo" session's
# tab bar). Without a per-home discriminator embedded in the actual
# title/name, two xo homes (two secondmates, a primary plus a
# secondmate, or two independent primary installations) whose task ids
# happen to collide can send/peek/close each other's tabs - the gap a
# captain-directed no-mistakes review gate caught for cmux
# (docs/cmux-backend.md) and this same tag mechanism was later ported to
# zellij to close for the same reason (docs/zellij-backend.md "Home-scoped
# tab titles").
#
# xo_backend_hometag() derives a short, stable tag: a readable prefix
# ("xo" for the primary home, "2ndmate-<id>" for a secondmate home
# carrying .xo-secondmate-home) plus a short hash of the resolved XO_ROOT
# path, so distinct installations - including multiple primaries on one
# machine - never collide even though they share one backend-global
# namespace. Callers source this file AFTER resolving their own
# XO_HOME/XO_ROOT fallbacks (both adapters already do this for their own
# purposes before any other function runs).
#
# Moving/relocating an xo installation changes its XO_ROOT path and
# therefore its tag; titles created under the old tag simply stop matching -
# an accepted limitation, no worse than the existing fact that a task's
# recorded absolute worktree path does not survive a move either.

XO_BACKEND_HOMETAG_SECONDMATE_MARKER=".xo-secondmate-home"

xo_backend_hometag() {
  local marker="$XO_HOME/$XO_BACKEND_HOMETAG_SECONDMATE_MARKER" id prefix root hash
  if [ -f "$marker" ]; then
    id=$(tr -d '[:space:]' < "$marker" 2>/dev/null)
    if [ -n "$id" ]; then
      prefix="2ndmate-$id"
    else
      prefix="xo"
    fi
  else
    prefix="xo"
  fi
  root=$(cd "$XO_ROOT" 2>/dev/null && pwd -P) || root=$XO_ROOT
  if command -v shasum >/dev/null 2>&1; then
    hash=$(printf '%s' "$root" | shasum -a 256 | awk '{print substr($1,1,8)}')
  elif command -v sha256sum >/dev/null 2>&1; then
    hash=$(printf '%s' "$root" | sha256sum | awk '{print substr($1,1,8)}')
  else
    hash=$(printf '%s' "$root" | cksum | awk '{printf "%08x", $1}')
  fi
  printf '%s-%s' "$prefix" "$hash"
}
