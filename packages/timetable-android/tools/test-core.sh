#!/usr/bin/env bash
# Run inside nix develop .#timetable-android-core. The core task needs no Android SDK; root plugin resolution may download AGP.
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
run_dir=${1:?Usage: test-core.sh ABSOLUTE_RUN_DIR ABSOLUTE_HEAVY_LOCK}
heavy_lock=${2:?Pass the shared heavy build lock}
case "$run_dir" in /*) ;; *) echo 'RUN_DIR must be absolute' >&2; exit 2;; esac
case "$heavy_lock" in /*) ;; *) echo 'lock must be absolute' >&2; exit 2;; esac
mkdir -p "$run_dir/home" "$run_dir/cache" "$run_dir/gradle" "$run_dir/tmp"
gradle_bin=$(command -v gradle)
java_bin=$(command -v java)
java_home=$(dirname -- "$(dirname -- "$(readlink -f -- "$java_bin")")")
cd -- "$project"
# Deliberate env allowlist: no Android variables, user sessions, credentials or inherited JVM flags.
exec env -i HOME="$run_dir/home" XDG_CACHE_HOME="$run_dir/cache" TMPDIR="$run_dir/tmp" \
  GRADLE_USER_HOME="$run_dir/gradle" JAVA_HOME="$java_home" \
  PATH="$java_home/bin:$(dirname -- "$gradle_bin"):/run/current-system/sw/bin" \
  SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
  flock "$heavy_lock" "$gradle_bin" --no-daemon --max-workers=2 :core:test
