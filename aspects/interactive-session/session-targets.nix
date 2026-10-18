{ lib, ... }:
{
  options.nixDotfiles.desktopSessionTargets = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    apply = lib.unique;
    internal = true;
    description = "Selected compositor targets that own the shared desktop services.";
  };
}
