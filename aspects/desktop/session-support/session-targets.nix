{ config, lib, ... }:
{
  options.nixDotfiles.graphicalSessionTargets = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    apply = lib.unique;
    internal = true;
    description = "Selected session targets sharing IME, X resources and audio sockets.";
  };
  config.systemd.user.targets =
    lib.genAttrs (map (lib.removeSuffix ".target") config.nixDotfiles.graphicalSessionTargets)
      (_: {
        Unit.Wants = [
          "pipewire.socket"
          "pipewire-pulse.socket"
        ];
      });
}
