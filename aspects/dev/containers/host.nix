{ lib, ... }:
{
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = false;
  };

  # NixOS's rootless module otherwise installs this user unit for every user
  # manager. The selected Home Manager binding installs the merged official
  # unit for only the account that chose local-containers.
  # force: Cancel the upstream global daemon wants; selected HM accounts own their daemon.
  systemd.user.services.docker.wantedBy = lib.mkForce [ ];
}
