{ lib, ... }:

{
  options.my.desktop.shell = lib.mkOption {
    type = lib.types.enum [
      "classic"
      "noctalia"
    ];
    default = "noctalia";
    description = "Select the desktop shell profile for the Home Manager session.";
  };
}
