#!/usr/bin/env bash

XO_CUSTOM_CHECK_HASH=
XO_CUSTOM_CHECK_SNAPSHOT=

xo_custom_check_sha256() {
  local file=$1
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" 2>/dev/null | awk '{print $1}'
  else
    return 1
  fi
}

xo_custom_check_trust_read() {
  local state=$1 id=$2 trust state_device version hash
  XO_CUSTOM_CHECK_HASH=
  xo_pr_task_id_valid "$id" || return 1
  [ -d "$state" ] && [ ! -L "$state" ] || return 1
  state_device=$(xo_pr_file_device "$state") || return 1
  trust="$state/$id.check-trust"
  xo_pr_private_file_valid "$trust" 600 "$state_device" || return 1
  exec 9< "$trust" || return 1
  IFS= read -r version <&9 || { exec 9<&-; return 1; }
  IFS= read -r hash <&9 || { exec 9<&-; return 1; }
  if IFS= read -r _extra <&9; then
    exec 9<&-
    return 1
  fi
  exec 9<&-
  [ "$version" = xo-custom-check-v1 ] || return 1
  [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || return 1
  XO_CUSTOM_CHECK_HASH=$hash
}

xo_custom_check_registered() {
  local state=$1 id=$2 check hash state_device
  check="$state/$id.check.sh"
  xo_custom_check_trust_read "$state" "$id" || return 1
  state_device=$(xo_pr_file_device "$state") || return 1
  xo_pr_private_file_valid "$check" 700 "$state_device" || return 1
  hash=$(xo_custom_check_sha256 "$check") || return 1
  [ "$hash" = "$XO_CUSTOM_CHECK_HASH" ]
}

xo_custom_check_snapshot_prepare() {
  local state=$1 id=$2 check hash state_device
  xo_custom_check_snapshot_cleanup
  check="$state/$id.check.sh"
  xo_custom_check_trust_read "$state" "$id" || return 1
  state_device=$(xo_pr_file_device "$state") || return 1
  xo_pr_private_file_valid "$check" 700 "$state_device" || return 1
  XO_CUSTOM_CHECK_SNAPSHOT=$(mktemp "$state/.xo-custom-check.XXXXXX") || return 1
  cp "$check" "$XO_CUSTOM_CHECK_SNAPSHOT" || { xo_custom_check_snapshot_cleanup; return 1; }
  chmod 0600 "$XO_CUSTOM_CHECK_SNAPSHOT" || { xo_custom_check_snapshot_cleanup; return 1; }
  [ -f "$XO_CUSTOM_CHECK_SNAPSHOT" ] && [ ! -L "$XO_CUSTOM_CHECK_SNAPSHOT" ] \
    || { xo_custom_check_snapshot_cleanup; return 1; }
  [ "$(xo_pr_file_mode "$XO_CUSTOM_CHECK_SNAPSHOT")" = 600 ] \
    || { xo_custom_check_snapshot_cleanup; return 1; }
  [ "$(xo_pr_file_device "$XO_CUSTOM_CHECK_SNAPSHOT")" = "$state_device" ] \
    || { xo_custom_check_snapshot_cleanup; return 1; }
  [ "$(xo_pr_file_link_count "$XO_CUSTOM_CHECK_SNAPSHOT")" = 1 ] \
    || { xo_custom_check_snapshot_cleanup; return 1; }
  hash=$(xo_custom_check_sha256 "$XO_CUSTOM_CHECK_SNAPSHOT") \
    || { xo_custom_check_snapshot_cleanup; return 1; }
  [ "$hash" = "$XO_CUSTOM_CHECK_HASH" ] || { xo_custom_check_snapshot_cleanup; return 1; }
}

xo_custom_check_snapshot_cleanup() {
  [ -z "$XO_CUSTOM_CHECK_SNAPSHOT" ] || rm -f -- "$XO_CUSTOM_CHECK_SNAPSHOT"
  XO_CUSTOM_CHECK_SNAPSHOT=
}
