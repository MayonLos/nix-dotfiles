# Package factory for the Noctalia components this repository uses.
#
# Every package pins an upstream revision with a fixed fetch hash and exposes
# its passthru metadata plus an updateScript. The experimental Umbriel session,
# its compositor, Luciole and the Umbriel portal were removed on 2026-11-27;
# only the shell and the login greeter remain.
#
# Expected wiring:
#   pkgs.local.noctaliaDesktop = import ../packages/noctalia-desktop { pkgs = final; };
#   pkgs.local.noctaliaDesktop.{noctalia,greeter}
{ pkgs, ... }:
{
  noctalia = pkgs.callPackage ./noctalia.nix { };
  greeter = pkgs.callPackage ./noctalia-greeter.nix { };

  # Upstream attribute name kept for callers/docs that use it.
  noctalia-greeter = pkgs.callPackage ./noctalia-greeter.nix { };
}
