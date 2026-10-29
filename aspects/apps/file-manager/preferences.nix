{ lib, pkgs, ... }:
let
  seed = pkgs.writeShellApplication {
    name = "thunar-seed-preferences";
    runtimeInputs = [
      pkgs.xfconf
      pkgs.gnugrep
    ];
    text = builtins.readFile ./resources/seed-preferences.sh;
  };
  # Boot-time HM can run before any graphical login. This private bus exposes
  # only Xfconf; its daemon flushes preferences when dbus-run-session exits.
  # The boot-time unit has no dbus-daemon on PATH, so name it explicitly.
  seedBus = pkgs.writeText "thunar-seed-session.conf" ''
    <busconfig>
      <type>session</type><listen>unix:tmpdir=/tmp</listen><auth>EXTERNAL</auth>
      <servicedir>${pkgs.xfconf}/share/dbus-1/services</servicedir>
      <policy context="default">
        <allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/>
      </policy>
    </busconfig>
  '';
in
{
  home.activation.seedThunarPreferences = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -n "''${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
      run ${seed}/bin/thunar-seed-preferences
    else
      thunar_runtime="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
      if [ -S "$thunar_runtime/bus" ]; then
        run ${pkgs.coreutils}/bin/env DBUS_SESSION_BUS_ADDRESS="unix:path=$thunar_runtime/bus" \
          ${seed}/bin/thunar-seed-preferences
      else
        run ${pkgs.dbus}/bin/dbus-run-session --dbus-daemon=${pkgs.dbus}/bin/dbus-daemon --config-file=${seedBus} -- \
          ${seed}/bin/thunar-seed-preferences
      fi
    fi
  '';
}
