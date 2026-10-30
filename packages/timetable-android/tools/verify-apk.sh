#!/usr/bin/env bash
set -euo pipefail
sdk=${ANDROID_HOME:?Enter nix develop .#android first}
for apk in "$@"; do
  manifest=$("$sdk/build-tools/35.0.0/aapt" dump xmltree "$apk" AndroidManifest.xml)
  if [[ "$manifest" =~ android.permission.INTERNET|android.permission.ACCESS_NETWORK_STATE|ai.onnxruntime.TelemetryInitializer ]]; then
    echo "FAIL: network/telemetry manifest entry in $apk" >&2
    exit 1
  fi
  "$sdk/build-tools/35.0.0/apksigner" verify --verbose "$apk"
  "$sdk/build-tools/35.0.0/aapt" dump badging "$apk" | sed -n '1,5p'
  echo "PASS: signed APK without network permissions or ORT telemetry initializer: $apk"
done
