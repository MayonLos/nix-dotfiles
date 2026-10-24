{ pkgs }:
# stlink 1.8 ships final MODE=0666 rules, unlike OpenOCD's seat-access rules.
# Keep its stable device aliases without granting every user USB write access.
pkgs.runCommand "stlink-seat-udev-rules" { } ''
  mkdir -p "$out/lib/udev/rules.d"
  for rule in ${pkgs.stlink}/lib/udev/rules.d/*.rules; do
    grep -Eq '^[[:space:]]*MODE:="0666"' "$rule"
    substitute "$rule" "$out/lib/udev/rules.d/$(basename "$rule")" \
      --replace-fail 'MODE:="0666"' 'MODE:="0660", TAG+="uaccess"'
  done
''
