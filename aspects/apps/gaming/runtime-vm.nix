{ pkgs, steamRun }:
let
  python = pkgs.python3.withPackages (packages: [
    packages.dbus-python
    packages.pygobject3
  ]);
  closeFds = pkgs.gamemode.runtimeProbe;
  ppdCli = pkgs.runCommand "gaming-ppd-cli" { } ''
    mkdir -p "$out/bin"
    # Install only the real CLI, leaving bus activation to the fixture.
    ln -s ${pkgs.power-profiles-daemon}/bin/powerprofilesctl "$out/bin/powerprofilesctl"
  '';
  dbusFixture = pkgs.runCommand "gaming-ppd-dbus-fixture" { } ''
    mkdir -p "$out/share/dbus-1/system.d" "$out/share/dbus-1/system-services"
    cat > "$out/share/dbus-1/system.d/org.freedesktop.UPower.PowerProfiles.conf" <<'EOF'
    <!DOCTYPE busconfig PUBLIC
      "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
      "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
    <busconfig>
      <policy context="default">
        <allow send_destination="org.freedesktop.UPower.PowerProfiles"/>
      </policy>
      <policy user="root">
        <allow own="org.freedesktop.UPower.PowerProfiles"/>
        <allow send_destination="org.freedesktop.UPower.PowerProfiles"/>
        <allow receive_sender="org.freedesktop.UPower.PowerProfiles"/>
      </policy>
    </busconfig>
    EOF
    cat > "$out/share/dbus-1/system-services/org.freedesktop.UPower.PowerProfiles.service" <<'EOF'
    [D-BUS Service]
    Name=org.freedesktop.UPower.PowerProfiles
    Exec=${python}/bin/python ${./resources/ppd-fixture.py} /var/lib/ppd-fixture/profile
    User=root
    EOF
  '';
in
pkgs.testers.runNixOSTest {
  name = "gaming-runtime";
  nodes.machine = {
    imports = [ ./host/gamemode.nix ];
    # force: the test framework also assigns pkgs; reuse our already-overlaid instance.
    nixpkgs.pkgs = pkgs.lib.mkForce pkgs;
    services = {
      dbus = {
        enable = true;
        packages = [ dbusFixture ];
      };
      power-profiles-daemon.enable = false;
    };
    environment = {
      systemPackages = [
        steamRun
        pkgs.lsof
        ppdCli
        python
      ];
      etc."ppd-fixture-initial-profile".text = "power-saver\n";
    };
    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [ "gamemode" ];
      linger = true;
    };
    systemd.tmpfiles.rules = [ "d /var/lib/ppd-fixture 0755 root root - -" ];
    systemd.services.ppd-fixture-state = {
      wantedBy = [ "multi-user.target" ];
      before = [ "dbus.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.coreutils}/bin/install -m 0644 /etc/ppd-fixture-initial-profile /var/lib/ppd-fixture/profile";
        RemainAfterExit = true;
      };
    };
  };

  testScript = ''
    import shlex

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")
    machine.wait_until_succeeds("test -S /run/user/1000/bus")

    def alice(command):
        return (
            "runuser -u alice -- env -i HOME=/home/alice "
            "XDG_RUNTIME_DIR=/run/user/1000 "
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
            "PATH=/run/current-system/sw/bin sh -c "
            + shlex.quote(command)
        )

    def profile():
        return machine.succeed(alice("powerprofilesctl get")).strip()

    machine.succeed("powerprofilesctl set power-saver")
    assert profile() == "power-saver", profile()

    # Launch a harmless process through the same env -> bash -> game boundary
    # used by Prism. Hold it open while inspecting GameMode and the inhibitor.
    machine.succeed(
        alice(
            "gamemoderun env SDL_VIDEODRIVER=wayland bash -c "
            "\"exec python3 -c 'import os,time; "
            "open(\\\"/tmp/game-smoke.pid\\\",\\\"w\\\").write(str(os.getpid())); "
            "time.sleep(90)'\" "
            ">/tmp/game-smoke.log 2>&1 &"
        )
    )
    machine.wait_until_succeeds(alice("gamemoded -s | grep -qi 'gamemode is active'"))
    machine.wait_for_unit("gaming-idle-inhibit.service", user="alice")
    machine.succeed(alice("systemctl --user is-active --quiet gaming-idle-inhibit.service"))
    machine.wait_until_succeeds("test \"$(powerprofilesctl get)\" = performance")
    assert profile() == "performance", profile()
    machine.succeed("systemd-inhibit --list | grep -q 'GameMode'")
    machine.wait_until_succeeds("test -s /tmp/game-smoke.pid")

    # Stopping the game must run the end hook, restore the profile, release its
    # logind inhibitor, and remove the transaction record.
    machine.succeed("kill $(cat /tmp/game-smoke.pid)")
    machine.wait_until_succeeds(alice("(gamemoded -s || true) | grep -qi 'gamemode is inactive'"))
    machine.wait_until_succeeds(alice("! systemctl --user is-active --quiet gaming-idle-inhibit.service"))
    machine.wait_until_succeeds("! systemd-inhibit --list | grep -q 'GameMode'")
    assert profile() == "power-saver", profile()
    machine.succeed("test ! -e /run/user/1000/gaming-mode/state.json")
    assert "gamemodeauto: \n" not in machine.succeed("cat /tmp/game-smoke.log")

    # A blacklisted wrapper may decline its own request, but it must not abort
    # the process chain. The final game's exit code must reach the caller.
    code, output = machine.execute(
        alice(
            "GAME_RUN_GPU=integrated game-run -- env SDL_VIDEODRIVER=wayland bash -c 'exit 7' "
            ">/tmp/game-exit.log 2>&1"
        )
    )
    assert code == 7, (code, output)
    machine.wait_until_succeeds(alice("(gamemoded -s || true) | grep -qi 'gamemode is inactive'"))
    assert profile() == "power-saver", profile()
    assert "gamemodeauto: \n" not in machine.succeed("cat /tmp/game-exit.log")
    game_logs = machine.succeed(alice("journalctl --user -b -u gamemoded --no-pager"))
    assert "ioprio value -2 invalid" not in game_logs
    assert "Skipping ioprio" not in game_logs

    # Exercise the same FHS environment as Steam's helper tools without
    # launching Steam itself. lsof closes many descriptors on exit.
    code, output = machine.execute(
        alice("steam-run sh -c 'test -z \"$LD_PRELOAD\" && lsof -v'")
    )
    assert code == 0, (code, output)
    assert "gamemodeauto:" not in output

    # Reproduce the steam-runtime lsof failure mode even without Valve's
    # downloaded helper: its main closes the library's cached D-Bus socket.
    disconnected = machine.succeed(alice("gamemoderun ${closeFds}/bin/gamemode-close-fds 2>&1"))
    assert "GameMode D-Bus connection closed before reply" in disconnected, disconnected
    machine.wait_until_succeeds(alice("(gamemoded -s || true) | grep -qi 'gamemode is inactive'"))
    machine.wait_until_succeeds("test \"$(powerprofilesctl get)\" = power-saver")

    # Daemon stop is an independent recovery path (no client remains).
    machine.succeed(
        alice(
            "gamemoderun python3 -c \"import os,time; "
            "open('/tmp/game-stop.pid','w').write(str(os.getpid())); time.sleep(90)\" "
            ">/tmp/game-stop.log 2>&1 &"
        )
    )
    machine.wait_until_succeeds(alice("gamemoded -s | grep -qi 'gamemode is active'"))
    machine.wait_until_succeeds("test -s /tmp/game-stop.pid && test \"$(powerprofilesctl get)\" = performance")
    machine.succeed(alice("systemctl --user kill --signal=SIGKILL gamemoded.service"))
    machine.wait_until_succeeds("test \"$(powerprofilesctl get)\" = power-saver")
    machine.wait_until_succeeds("! systemd-inhibit --list | grep -q 'GameMode'")
    machine.succeed("kill -9 $(cat /tmp/game-stop.pid) 2>/dev/null || true")
    assert not machine.succeed("journalctl -b _COMM=pkexec --quiet --no-pager -o cat").strip()
  '';
}
