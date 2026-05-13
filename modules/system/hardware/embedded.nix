{ pkgs, ... }:
{
  services.udev.packages = [
    pkgs.stlink
    pkgs.openocd
  ];

  users.groups.plugdev = { };
  users.users.mayon.extraGroups = [
    "plugdev"
    "dialout"
  ];
}
