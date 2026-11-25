#!/usr/bin/env bash
# Collect two idle snapshots per login. Never fails the unit: every field is
# best-effort so a missing compositor/tool only yields 0 or null.
set -uo pipefail

out_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noctalia-bench"
mkdir -p "$out_dir"
session="${XDG_CURRENT_DESKTOP:-unknown}"
stamp="$(date +%Y%m%dT%H%M%S)"

rss_kb() {
  ps -eo rss=,comm= | awk -v pat="$1" '$2 ~ pat { s += $1 } END { print s + 0 }'
}
mem_current() {
  systemctl --user show "$1" -p MemoryCurrent --value 2>/dev/null | awk 'NF && $1 != "[not" { print $1; exit }' || true
}

collect() {
  local kind="$1"
  local out="$out_dir/${session}-${stamp}-${kind}.json"
  local iso
  iso="$(date -Is)"
  {
    printf '{\n'
    printf '  "session": "%s",\n' "$session"
    printf '  "kind": "%s",\n' "$kind"
    printf '  "timestamp": "%s",\n' "$iso"
    printf '  "user_slice_bytes": %s,\n' "$(systemctl show "user-$(id -u).slice" -p MemoryCurrent --value 2>/dev/null || echo null)"
    printf '  "noctalia_unit_bytes": %s,\n' "$(mem_current noctalia.service || echo null)"
    printf '  "running_user_services": %s,\n' "$(systemctl --user list-units --type=service --state=running --no-legend --plain 2>/dev/null | wc -l)"
    printf '  "compositor_rss_kb": %s,\n' "$(rss_kb '^(mango|umbriel|Hyprland)$|^\.umbriel-wrappe$')"
    printf '  "noctalia_rss_kb": %s,\n' "$(rss_kb '^\.noctalia-wrapp$|^noctalia$')"
    printf '  "fcitx5_rss_kb": %s,\n' "$(rss_kb '^\.fcitx5-wrapped$|^fcitx5$')"
    printf '  "xwayland_rss_kb": %s,\n' "$(rss_kb '^Xwayland$')"
    printf '  "clipboard_bridge_rss_kb": %s,\n' "$(rss_kb 'clipboard-bridg')"
    printf '  "polkit_agent_rss_kb": %s,\n' "$(rss_kb 'polkit-gnome')"
    printf '  "nvidia": "%s"\n' "$(nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv,noheader 2>/dev/null | head -1 || true)"
    printf '}\n'
  } >"$out.tmp" 2>/dev/null
  mv "$out.tmp" "$out" 2>/dev/null || true
}

sleep 90
collect early
sleep 210
collect idle
