{ inputs, pkgs }:
inputs.noctalia-greeter.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./tech-greeter.patch ];
  postPatch = (old.postPatch or "") + ''
    grep -F 'm_passwordField->setFlatStyle(true)' src/greeter/greeter_surface.cpp
    grep -F 'R41: compact transparent identity group' src/greeter/greeter_surface.cpp
    grep -F 'Style::scaled(160.0f)' src/greeter/greeter_surface.cpp
    grep -F 'pango_attr_font_features_new("tnum=1")' src/render/text/cairo_text_renderer.cpp
    grep -F 'blockY = oy + sh * (sh < Style::scaled(700.0f)' src/greeter/greeter_surface.cpp
  '';
})
