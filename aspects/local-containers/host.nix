{ lib, ... }:
{
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = false;
  };

  # NixOS's rootless module otherwise installs this user unit for every user
  # manager. The selected Home Manager binding installs the merged official
  # unit for only the account that chose local-containers.
  systemd.user.services.docker.wantedBy = lib.mkForce [ ];
}
