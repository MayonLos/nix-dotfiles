{ pkgs }:
pkgs.local.herdr.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./tab-underline.patch ];
  postPatch = (old.postPatch or "") + ''
    grep -F '.add_modifier(Modifier::UNDERLINED);' src/client/shell/tabs.rs
    grep -F '.bg(palette.panel_bg)' src/client/shell/tabs.rs
  '';
})
