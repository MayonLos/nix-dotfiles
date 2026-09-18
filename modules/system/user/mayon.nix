{ pkgs, ... }:
{
  users.users.mayon = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "gamemode"
      "input"
      # /dev/ttyUSB* and /dev/ttyACM* are root:dialout, and unlike the debug
      # probes (hardware/debug-probes.nix) they carry no uaccess tag -- so the
      # board's serial console needs real group membership.
      "dialout"
    ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      tree
    ];
  };
}
