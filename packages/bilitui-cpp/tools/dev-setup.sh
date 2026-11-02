#!/usr/bin/env bash
# Generates what clangd and a local build need but Git must not hold: the
# palette and build/compile_commands.json. Rerun after flake.lock changes or a
# garbage collection, because the database records Nix store paths.
# debugoptimized because Nix fortify warns at -O0 and the project uses -Werror.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
nix eval --raw --no-write-lock-file --impure --expr \
  'import ./tools/palette.nix (import ../../aspects/appearance/appearance/onedark.nix)' \
  >src/ui/palette.inc
nix develop --no-write-lock-file ../..#cpp --command meson setup --wipe --buildtype=debugoptimized build
