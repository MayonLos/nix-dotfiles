{
  pkgs,
  nixos,
  home,
  ...
}:
let
  tool = import ./conservation.nix { inherit pkgs; };
in
{
  legion-conservation =
    assert builtins.elem pkgs.powerMayon home.home.packages;
    assert home.systemd.user.timers.power-mayon-auto.Timer.OnCalendar == "*-*-* *:*:00,30";
    assert home.systemd.user.services.power-mayon-auto.Service.NoNewPrivileges;
    assert nixos.services.power-profiles-daemon.enable;
    assert !nixos.services.tlp.enable;
    assert builtins.elem "power-mayon" nixos.users.users.mayon.extraGroups;
    assert pkgs.lib.hasInfix pkgs.powerMayon.profilePolicy nixos.security.polkit.extraConfig;
    assert nixos.users.groups ? legion-conservation;
    assert builtins.elem "legion-conservation" nixos.users.users.mayon.extraGroups;
    assert pkgs.lib.hasInfix "DRIVER==\"ideapad_acpi\"" nixos.services.udev.extraRules;
    assert pkgs.lib.hasInfix "chmod g+w /sys%p/conservation_mode" nixos.services.udev.extraRules;
    pkgs.runCommand "legion-conservation-check" { } ''
      mkdir -p "$TMPDIR/sys/device"
      substitute ${tool}/bin/legion-conservation "$TMPDIR/tool" \
        --replace-fail '/sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode' "$TMPDIR/sys/*/conservation_mode"
      chmod +x "$TMPDIR/tool"
      test -z "$("$TMPDIR/tool" status)"
      if "$TMPDIR/tool" toggle; then exit 1; fi
      printf '0\n' > "$TMPDIR/sys/device/conservation_mode"
      test -z "$("$TMPDIR/tool" status)"
      "$TMPDIR/tool" toggle
      test "$(cat "$TMPDIR/sys/device/conservation_mode")" = 1
      test "$("$TMPDIR/tool" status)" = 养护
      "$TMPDIR/tool" toggle
      test "$(cat "$TMPDIR/sys/device/conservation_mode")" = 0
      printf '2\n' > "$TMPDIR/sys/device/conservation_mode"
      if "$TMPDIR/tool" toggle; then exit 1; fi
      test "$(cat "$TMPDIR/sys/device/conservation_mode")" = 2
      printf '0\n' > "$TMPDIR/sys/device/conservation_mode"
      mkdir "$TMPDIR/sys/second"
      printf '0\n' > "$TMPDIR/sys/second/conservation_mode"
      if "$TMPDIR/tool" toggle; then exit 1; fi
      test "$(cat "$TMPDIR/sys/device/conservation_mode")" = 0
      test "$(cat "$TMPDIR/sys/second/conservation_mode")" = 0
      rm "$TMPDIR/sys/second/conservation_mode"
      "$TMPDIR/tool" on
      test "$(cat "$TMPDIR/sys/device/conservation_mode")" = 1
      "$TMPDIR/tool" on
      test "$(cat "$TMPDIR/sys/device/conservation_mode")" = 1
      "$TMPDIR/tool" off
      "$TMPDIR/tool" off
      test "$(cat "$TMPDIR/sys/device/conservation_mode")" = 0
      touch "$out"
    '';
}
