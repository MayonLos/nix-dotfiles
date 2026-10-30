#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
run_dir=${1:?Usage: render-prototype.sh ABSOLUTE_RUN_DIR ABSOLUTE_SHOTS_DIR}
shots=${2:?Pass the screenshots directory}
case "$run_dir:$shots" in /*:/*) ;; *) echo 'Use absolute paths' >&2; exit 2;; esac
chromium_bin=$(command -v chromium)
mkdir -p "$run_dir/home" "$run_dir/config" "$run_dir/cache" "$shots"
for screen in today week review import; do
    env -i HOME="$run_dir/home" XDG_CONFIG_HOME="$run_dir/config" XDG_CACHE_HOME="$run_dir/cache" \
      PATH=/run/current-system/sw/bin:/usr/bin:/bin \
      "$chromium_bin" --headless=new --disable-gpu --no-sandbox --hide-scrollbars \
      --no-first-run --disable-background-networking --disable-sync \
      --host-resolver-rules='MAP * ~NOTFOUND' --force-device-scale-factor=1 \
      --window-size=1080,2400 --user-data-dir="$run_dir/profile-$screen" \
      --screenshot="$shots/$screen.png" "file://$project/prototype/index.html?screen=$screen&zoom=3" \
      >"$run_dir/$screen.log" 2>&1
done
