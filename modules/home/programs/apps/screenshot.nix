{
  pkgs,
  inputs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  # Replaces the hand-rolled `slurp -d | grim -g | satty` pipeline.
  #
  # mark-shot does region select, annotate, copy, save and pin-to-desktop in one
  # program, and its README states it targets Wayland compositors like niri. It
  # still calls grim and wl-clipboard internally, so those packages stay; satty
  # had no other user and is gone from packages.nix.
  #
  # wayscrollshot does scrolling capture (scroll and stitch) for long web pages
  # and long chat logs -- something the old pipeline could not do at all. It
  # needs slurp and grim at runtime.
  home.packages = [
    inputs.mark-shot.packages.${system}.default
    inputs.wayscrollshot.packages.${system}.default
  ];
}
