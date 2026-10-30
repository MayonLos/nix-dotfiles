#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
repo=$(cd -- "$project/../.." && pwd)
run=${TIMETABLE_RUN_DIR:-/home/mayon/nix-dotfiles/.work/r50/android/run}
mkdir -p "$run/android-home" "$run/gradle" "$run/android-cache" "$run/tmp"
cd -- "$repo"
exec env -i HOME="$run/android-home" XDG_CACHE_HOME="$run/android-cache" TMPDIR="$run/tmp" \
  GRADLE_USER_HOME="$run/gradle" PATH=/run/current-system/sw/bin:/usr/bin:/bin \
  SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
  flock /home/mayon/nix-dotfiles/.work/r50/heavy.lock \
  nix develop --no-write-lock-file .#android --command bash -c \
  'cd -- "$1"; shift; exec gradle --no-daemon --max-workers=2 -PenableAndroid=true "$@"' bash "$project" "$@"
