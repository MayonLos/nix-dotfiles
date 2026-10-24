{ pkgs, source }:

pkgs.runCommand "noctalia-community-plugins" { nativeBuildInputs = [ pkgs.luau ]; } ''
  mkdir -p "$out"

  for plugin in ${source}/*; do
    [ -d "$plugin" ] || continue
    name="''${plugin##*/}"
    case "$name" in
      mango_layouts|nix-status) ;;
      *) ln -s "$plugin" "$out/$name" ;;
    esac
  done

  cp -r ${source}/mango_layouts "$out/mango_layouts"
  cp -r ${source}/nix-status "$out/nix-status"
  chmod -R u+w "$out/mango_layouts" "$out/nix-status"

  cp ${../resources/noctalia-community/mango_layouts/translations/zh-CN.json} \
    "$out/mango_layouts/translations/zh-CN.json"
  cp ${../resources/noctalia-community/nix-status/widget.luau} "$out/nix-status/widget.luau"
  cp ${../resources/noctalia-community/nix-status/generation_number.luau} \
    "$out/nix-status/generation_number.luau"
  cp ${../resources/noctalia-community/nix-status/tests/generation_number_test.luau} \
    "$out/nix-status/tests/generation_number_test.luau"
  luau "$out/nix-status/tests/generation_number_test.luau"
''
