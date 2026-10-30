{
  pkgs,
  nixos,
  home,
  ...
}:
let
  inherit (pkgs) lib;
  lease = nixos.systemd.services."mcsrv-firewall@";
  helper = field: builtins.head (lib.splitString " " lease.serviceConfig.${field});
in
{
  mcsrv-service-policy =
    assert lease.wantedBy == [ ];
    assert lease.serviceConfig.RuntimeMaxSec == "90s";
    assert lease.serviceConfig.Restart == "no";
    assert lease.serviceConfig.ProtectHome;
    assert !nixos.services.mcsrv-mayon.tailscale.enable;
    assert builtins.elem "mcsrv-firewall" nixos.users.users.mayon.extraGroups;
    assert builtins.elem pkgs.mcsrvMayon home.home.packages;
    assert lib.hasInfix "mcsrv-firewall@2556" nixos.security.polkit.extraConfig;
    pkgs.runCommand "mcsrv-service-policy-check" { } ''
      test -x ${helper "ExecStartPre"}
      test -x ${helper "ExecStopPost"}
      ${pkgs.bash}/bin/bash -n ${helper "ExecStartPre"}
      ${pkgs.bash}/bin/bash -n ${helper "ExecStopPost"}
      touch "$out"
    '';
}
