#!/usr/bin/env bash
# Run inside nix develop .#android. Passwords are read by apksigner from private files.
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
key_dir=${TIMETABLE_KEY_DIR:-/home/mayon/.local/share/timetable-android}
out=${1:-/home/mayon/nix-dotfiles/.work/r50/android/apk}
sdk=${ANDROID_HOME:?Enter nix develop .#android first}
for private in "$key_dir/keystore" "$key_dir/keystore.password"; do
  test -f "$private"
  test "$(stat -c '%a' "$private")" = 600 || { echo 'Signing files must have mode 0600' >&2; exit 1; }
done
mkdir -p "$out"
work=$(mktemp -d "$out/.signing.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
"$sdk/build-tools/35.0.0/zipalign" -P 16 -f 4 "$project/app/build/outputs/apk/release/app-release-unsigned.apk" "$work/aligned.apk"
"$sdk/build-tools/35.0.0/apksigner" sign --ks "$key_dir/keystore" --ks-pass "file:$key_dir/keystore.password" --out "$work/release.apk" "$work/aligned.apk"
"$sdk/build-tools/35.0.0/apksigner" verify --verbose --print-certs "$work/release.apk"
cp -- "$work/release.apk" "$out/timetable-mayon-0.2.0-release.apk"
cp -- "$project/app/build/outputs/apk/debug/app-debug.apk" "$out/timetable-mayon-0.2.0-debug.apk"
sha256sum "$out/"*.apk
