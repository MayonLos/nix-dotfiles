{
  pkgs,
  powerMayon ? pkgs.powerMayon,
}:
let
  backendScript = "${powerMayon}/share/power-mayon/backend.py";
in
pkgs.testers.runNixOSTest {
  name = "power-mayon";
  nodes.machine = {
    # force: the VM must use the shared overlay instance that provides powerMayon.
    nixpkgs.pkgs = pkgs.lib.mkForce pkgs;
    security.polkit = {
      enable = true;
      extraConfig = powerMayon.profilePolicy;
    };
    users = {
      groups.power-mayon = { };
      users = {
        power-test = {
          isNormalUser = true;
          uid = 1000;
          createHome = true;
          extraGroups = [ "power-mayon" ];
        };
        outsider = {
          isNormalUser = true;
          uid = 1001;
          createHome = true;
        };
      };
    };
    environment.systemPackages = [
      pkgs.python3
      pkgs.polkit
      pkgs.power-profiles-daemon
      powerMayon
    ];
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
  };

  testScript = ''
    import json
    import shlex

    machine.wait_for_unit("multi-user.target")
    machine.succeed("systemctl start polkit.service")
    machine.wait_for_unit("polkit.service")

    def check_policy(user, uid, action):
        command = (
            "runuser -u " + user + " -- env -i HOME=/home/" + user
            + " USER=" + user + " LOGNAME=" + user
            + " PATH=/run/current-system/sw/bin XDG_RUNTIME_DIR=/run/user/" + uid
            + " sh -c " + shlex.quote(
                "pkcheck --action-id " + shlex.quote(action) + " --process $$"
            )
        )
        return machine.execute(command)

    switch_action = "org.freedesktop.UPower.PowerProfiles.switch-profile"
    hold_action = "org.freedesktop.UPower.PowerProfiles.hold-profile"
    configure_action = "org.freedesktop.UPower.PowerProfiles.configure-action"
    assert check_policy("power-test", "1000", switch_action)[0] == 0
    assert check_policy("outsider", "1001", switch_action)[0] != 0
    assert check_policy("power-test", "1000", hold_action)[0] != 0
    assert check_policy("power-test", "1000", configure_action)[0] != 0

    # All control surfaces and hardware data are private writable fixtures owned
    # by the unprivileged test account. No test command can reach real sysfs.
    machine.succeed("install -d -o power-test -g users /home/power-test/bin /home/power-test/config /home/power-test/state /home/power-test/runtime /home/power-test/sys/class/power_supply/AC /home/power-test/sys/class/power_supply/BAT0 /home/power-test/sys/bus/platform/drivers/ideapad_acpi/fixture /home/power-test/proc")
    machine.succeed("printf 'balanced\\n' > /home/power-test/profile; printf 'Mains\\n' > /home/power-test/sys/class/power_supply/AC/type; printf '0\\n' > /home/power-test/sys/class/power_supply/AC/online; printf 'Battery\\n' > /home/power-test/sys/class/power_supply/BAT0/type; printf 'Discharging\\n' > /home/power-test/sys/class/power_supply/BAT0/status; printf '0\\n' > /home/power-test/sys/bus/platform/drivers/ideapad_acpi/fixture/conservation_mode; chown -R power-test:users /home/power-test")
    machine.succeed("cat > /home/power-test/bin/powerprofilesctl <<'EOF'\n#!/bin/sh\nset -eu\ncase \"$1\" in\n get) cat /home/power-test/profile ;;\n list) printf 'power-saver:\\nbalanced:\\nperformance:\\n' ;;\n set) printf '%s\\n' \"$2\" >> /home/power-test/ppd.log; printf '%s\\n' \"$2\" > /home/power-test/profile ;;\n *) exit 2 ;;\nesac\nEOF\ncat > /home/power-test/bin/legion-conservation <<'EOF'\n#!/bin/sh\nset -eu\nprintf '%s\\n' \"$1\" >> /home/power-test/conservation.log\ncase \"$1\" in\n status) test \"$(cat /home/power-test/sys/bus/platform/drivers/ideapad_acpi/fixture/conservation_mode)\" = 1 && echo 养护 || : ;;\n on) echo 1 > /home/power-test/sys/bus/platform/drivers/ideapad_acpi/fixture/conservation_mode ;;\n off) echo 0 > /home/power-test/sys/bus/platform/drivers/ideapad_acpi/fixture/conservation_mode ;;\n *) exit 2 ;;\nesac\nEOF\nchmod +x /home/power-test/bin/*; chown -R power-test:users /home/power-test")

    backend_script = ${builtins.toJSON backendScript}

    def run_as_test(command, expected=0, production=False):
        env = (
            "env -i HOME=/home/power-test USER=power-test LOGNAME=power-test "
            "PATH=/home/power-test/bin:/run/current-system/sw/bin "
            "XDG_CONFIG_HOME=/home/power-test/config XDG_STATE_HOME=/home/power-test/state "
            "XDG_RUNTIME_DIR=/home/power-test/runtime "
            "POWER_MAYON_SYSFS=/home/power-test/sys POWER_MAYON_PROCFS=/home/power-test/proc "
            "sh -c "
        )
        executable = "power-mayon" if production else "python3 " + shlex.quote(backend_script)
        code, output = machine.execute(
            "runuser -u power-test -- " + env + shlex.quote(executable + " " + command)
        )
        assert code == expected, (command, code, output)
        return output

    # Exercise the installed wrapper once. Its pinned PPD PATH is tested read-only;
    # control mutations below call its bundled backend with the isolated mock PATH.
    status = json.loads(run_as_test("status --json", production=True))
    assert isinstance(status, dict), status
    assert "自动规则关闭" in run_as_test("auto tick")
    assert machine.succeed("cat /home/power-test/profile").strip() == "balanced"
    assert not machine.succeed("test -e /home/power-test/ppd.log && cat /home/power-test/ppd.log || true").strip()

    run_as_test("mode power-saver")
    assert machine.succeed("cat /home/power-test/profile").strip() == "power-saver"
    before = machine.succeed("cat /home/power-test/ppd.log")
    run_as_test("mode turbo", expected=2)
    assert machine.succeed("cat /home/power-test/ppd.log") == before

    # Automatic policy is opt-in, applies AC/battery rules, and yields to the
    # existing GameMode transaction while that transaction owns the profile.
    run_as_test("auto configure --ac performance --battery power-saver")
    run_as_test("auto enable")
    run_as_test("auto tick")
    assert machine.succeed("cat /home/power-test/profile").strip() == "power-saver"
    machine.succeed("printf '1\\n' > /home/power-test/sys/class/power_supply/AC/online")
    run_as_test("auto tick")
    assert machine.succeed("cat /home/power-test/profile").strip() == "performance"
    machine.succeed("install -d -m 0700 -o power-test -g users /home/power-test/runtime/gaming-mode; printf '{\"active\":true,\"profile\":\"balanced\"}\\n' > /home/power-test/runtime/gaming-mode/state.json; chown power-test:users /home/power-test/runtime/gaming-mode/state.json")
    machine.succeed("printf 'balanced\\n' > /home/power-test/profile")
    run_as_test("auto configure --gamemode performance")
    assert "GameMode 规则: performance" in run_as_test("auto tick")
    assert machine.succeed("cat /home/power-test/profile").strip() == "performance"
    assert json.loads(machine.succeed("cat /home/power-test/runtime/gaming-mode/state.json")) == {
        "active": True, "profile": "balanced"
    }
    run_as_test("auto configure --gamemode keep")
    assert "GameMode" in run_as_test("auto tick")
    assert machine.succeed("cat /home/power-test/profile").strip() == "performance"
    assert json.loads(machine.succeed("cat /home/power-test/runtime/gaming-mode/state.json")) == {
        "active": True, "profile": "balanced"
    }
    machine.succeed("printf 'balanced\\n' > /home/power-test/profile")
    machine.succeed("rm /home/power-test/runtime/gaming-mode/state.json")
    run_as_test("auto tick")
    assert machine.succeed("cat /home/power-test/profile").strip() == "performance"
    machine.succeed("printf '{\"active\":false,\"profile\":\"balanced\"}\\n' > /home/power-test/runtime/gaming-mode/state.json")
    run_as_test("auto configure --gamemode performance")
    machine.succeed("printf 'balanced\\n' > /home/power-test/profile")
    assert "让出 GameMode" in run_as_test("auto tick")
    assert machine.succeed("cat /home/power-test/profile").strip() == "balanced"
    machine.succeed("printf '{\"active\":true,\"profile\":\"turbo\"}\\n' > /home/power-test/runtime/gaming-mode/state.json")
    assert "让出 GameMode" in run_as_test("auto tick")
    assert machine.succeed("cat /home/power-test/profile").strip() == "balanced"
    machine.succeed("rm /home/power-test/runtime/gaming-mode/state.json")
    run_as_test("auto disable")

    run_as_test("conservation on")
    assert machine.succeed("cat /home/power-test/sys/bus/platform/drivers/ideapad_acpi/fixture/conservation_mode").strip() == "1"
    run_as_test("conservation off")
    assert machine.succeed("cat /home/power-test/sys/bus/platform/drivers/ideapad_acpi/fixture/conservation_mode").strip() == "0"
    assert machine.succeed("tail -n 2 /home/power-test/conservation.log").splitlines() == ["on", "off"]
  '';
}
