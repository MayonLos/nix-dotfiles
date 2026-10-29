{ pkgs }:

pkgs.btop.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./btop-compact.patch ];
})
