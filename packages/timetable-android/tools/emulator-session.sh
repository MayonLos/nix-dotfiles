#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
repo=$(cd -- "$project/../.." && pwd)
run=/home/mayon/nix-dotfiles/.work/r50/android/run
mkdir -p "$run/phase2/avd" "$run/phase2/emulator-home" "$run/phase2/emulator-user" "$run/android-cache" "$run/tmp"
cd -- "$repo"
exec env -i HOME="$run/android-home" XDG_CACHE_HOME="$run/android-cache" TMPDIR="$run/tmp" \
  GRADLE_USER_HOME="$run/gradle" ANDROID_AVD_HOME="$run/phase2/avd" \
  ANDROID_USER_HOME="$run/phase2/emulator-user" ANDROID_ADB_SERVER_PORT=5039 ADB_SERVER_SOCKET=tcp:localhost:5039 \
  PATH=/run/current-system/sw/bin:/usr/bin:/bin SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
  flock /home/mayon/nix-dotfiles/.work/r50/heavy.lock \
  nix develop --no-write-lock-file .#android --command bash --noprofile --norc -i
