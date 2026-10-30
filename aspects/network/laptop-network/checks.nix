{ pkgs, nixos, ... }:
let
  service = nixos.systemd.services.mayon-clash;
in
assert service.wantedBy == [ ];
assert service.wants == [ "network-online.target" ];
assert service.serviceConfig.User == nixos.services.mayon-clash.user;
assert service.serviceConfig.RuntimeDirectoryMode == "0700";
assert service.serviceConfig.NoNewPrivileges;
assert service.serviceConfig.ProtectHome == "read-only";
assert service.enable;
assert (service.serviceConfig.Restart or "no") == "no";
assert builtins.elem "mayon-clash" nixos.networking.firewall.trustedInterfaces;
assert !(nixos.systemd.services.nix-daemon.environment ? HTTPS_PROXY);
{
  laptop-network = pkgs.runCommand "laptop-network-check" { } "touch $out";
  mayon-clash-vm = pkgs.testers.runNixOSTest {
    name = "mayon-clash-manual";
    nodes.machine = { pkgs, lib, ... }: {
      imports = [ ./native-clash.nix ];
      virtualisation.memorySize = 2048;
      virtualisation.cores = 2;
      users.users.trial = {
        isNormalUser = true;
        uid = 1000;
      };
      services.mayon-clash.user = "trial";
      networking.dhcpcd.denyInterfaces = [ "mayon-clash" ];
      environment.systemPackages = [
        pkgs.mayonTui.clash
        pkgs.curl
        pkgs.python3
        pkgs.bind.dnsutils
      ];
      systemd.services = {
        # force: synthetic VM diagnostics only; production suppresses core stdout to protect credentials.
        mayon-clash.serviceConfig.StandardOutput = lib.mkForce "journal";
        unrelated.script = "sleep infinity";
        synthetic-subscription = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${./tests/subscription-server.py}";
        };
      };
    };
    testScript = builtins.readFile ./tests/native-vm.py;
  };
}
