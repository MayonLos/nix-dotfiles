{ pkgs ? import <nixpkgs> { config.allowUnfree = true; } }:

import ./shell.nix { inherit pkgs; }
