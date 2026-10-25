{ pkgs }:
assert pkgs.swayimg.version == "4.7";
pkgs.swayimg.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./resources/swayimg-shellcmd-safe-path.patch ];
})
