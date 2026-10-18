{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    let
      pkgs-unstable = import inputs.nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # Single unstable instantiation: inventory/hosts/nixos-btw/default.nix consumes it through
      # withSystem's module args, and the portal-wlr overlay below takes
      # its package from the same set.
      _module.args.pkgs-unstable = pkgs-unstable;

      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          # xdg-desktop-portal-wlr is what serves ScreenCast under mango.
          # Stable is 0.8.2; 0.8.3 took over driving the PipeWire graph and
          # 0.8.4 fixed streams freezing on PipeWire buffer starvation --
          # both squarely in the "screen share dies after a while" class.
          #
          # It has to be an overlay rather than a package option:
          # nixos/modules/config/xdg/portals/wlr.nix hardcodes
          # `pkgs.xdg-desktop-portal-wlr` for BOTH the extraPortals entry
          # and the systemd ExecStart it overrides, and mango's own module
          # adds the same attribute again. Listing an unstable copy
          # alongside would put two different versions of one backend on the
          # bus. Taken from the single pkgs-unstable instantiation above,
          # not a second legacyPackages evaluation.
          (_: _: {
            inherit (pkgs-unstable) xdg-desktop-portal-wlr;
          })
        ];
      };
    };
}
