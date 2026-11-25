# Package factory for the Noctalia desktop stack (experimental, 2026-11).
#
# Every package pins an upstream revision with a fixed fetch hash; each
# derivation exposes `passthru.version` and `passthru.rev` (or tag) plus an
# `updateScript`. See README.md for provenance and .work/research/ for the
# build evidence report.
#
# Expected wiring (aspects are owned by another change):
#   pkgs.local.noctaliaDesktop = import ../packages/noctalia-desktop { pkgs = final; };
#   pkgs.local.noctaliaDesktop.{noctalia,luciole,umbriel,noctalia-greeter,portal}
{ pkgs, ... }:
let
  noctalia = pkgs.callPackage ./noctalia.nix { };
  umbriel = pkgs.callPackage ./umbriel.nix { };
  greeter = pkgs.callPackage ./noctalia-greeter.nix { };
  luciole = pkgs.callPackage ./luciole.nix { };
  portal = pkgs.callPackage ./xdg-desktop-portal-umbriel.nix { };
in
{
  inherit
    noctalia
    luciole
    umbriel
    greeter
    portal
    ;

  # The greeter's upstream attribute name.
  noctalia-greeter = greeter;

  # The portal's upstream attribute name, kept so consumers can use either key.
  xdg-desktop-portal-umbriel = portal;

  # Verbatim copies of the upstream v5.6.0 module files. They are plain imports;
  # the caller wires the package option to the derivations above.
  modules = {
    noctalia = {
      homeManager = ./modules/noctalia/home-module.nix;
      nixos = ./modules/noctalia/nixos-module.nix;
      hjem = ./modules/noctalia/hjem-module.nix;
    };
  };
}
