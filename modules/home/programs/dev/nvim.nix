{
  pkgs,
  inputs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  # The nixvim modules in ../../../../nixvim reference `pkgs.mcp-hub`, which is
  # not in nixpkgs — the standalone flake used to inject it with an overlay on
  # its own `_module.args.pkgs`. Reproducing that here keeps the config files
  # byte-identical to what they were in the separate repo.
  #
  # This is a second nixpkgs instantiation rather than an overlay on the shared
  # `pkgs`, because putting it on the system-wide one would rebuild every
  # package that transitively depends on stdenv for the sake of one editor.
  nvimPkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      (_: _: { mcp-hub = inputs.mcp-hub.packages.${system}.default; })
    ];
  };

  # ./nixvim lives at the repo root on purpose. lib/import-dir.nix walks every
  # directory under modules/home/ and imports each .nix file it finds as a Home
  # Manager module — a nixvim module tree placed there would be loaded as ~70
  # broken HM modules.
  nvim = inputs.nixvim.legacyPackages.${system}.makeNixvimWithModule {
    pkgs = nvimPkgs;
    module = import ../../../../nixvim;
  };
in
{
  home.packages = [ nvim ];
}
