{ pkgs }:

pkgs.lazygit.overrideAttrs (old: {
  # gocui already separates title and frame drawing; upstream ties the two
  # colors together at these three assignments. Patch failure guards upgrades.
  patches = (old.patches or [ ]) ++ [ ./lazygit-title-focus.patch ];
})
