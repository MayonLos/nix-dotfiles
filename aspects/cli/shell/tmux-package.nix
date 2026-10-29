{ pkgs }:

pkgs.tmux.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./tmux-passthrough.patch ];
})
