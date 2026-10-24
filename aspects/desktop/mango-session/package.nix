# Private package factory shared by the host session and HM configuration.
{ inputs, pkgs }:
inputs.mango.packages.${pkgs.stdenv.hostPlatform.system}.mango.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./focused-shadow.patch ];
  postPatch = (old.postPatch or "") + ''
    # Fail on upstream drift instead of silently losing focus elevation.
    grep -F 'float focused_shadowscolor[4];' include/mango/config/parse.h
    grep -F 'strcmp(key, "focused_shadows_color")' src/config/option_defs.c
    grep -F 'focused ? config.focused_shadowscolor : config.shadowscolor' src/manage/client.c
    grep -F 'wlr_scene_shadow_set_color(c->shadow,' src/manage/client.c
  '';
})
