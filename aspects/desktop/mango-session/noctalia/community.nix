{ pkgs, source }:

pkgs.runCommand "noctalia-community-plugins" { nativeBuildInputs = [ pkgs.luau ]; } ''
  mkdir -p "$out"

  for plugin in ${source}/*; do
    [ -d "$plugin" ] || continue
    name="''${plugin##*/}"
    case "$name" in
      mango_layouts|portctl|mini-docker) ;;
      *) ln -s "$plugin" "$out/$name" ;;
    esac
  done

  cp -r ${source}/mango_layouts "$out/mango_layouts"
  cp -r ${source}/portctl "$out/portctl"
  cp -r ${source}/mini-docker "$out/mini-docker"
  chmod -R u+w "$out/mango_layouts" "$out/portctl" "$out/mini-docker"
  mkdir -p "$out/portctl/tests" "$out/mini-docker/tests"

  # Upstream API anchors: these overrides retain the plugin state and actions.
  grep -Fq '"docker_snapshot"' ${source}/mini-docker/widget.luau
  grep -Fq 'noctalia.togglePanel(PANEL_ID)' ${source}/mini-docker/widget.luau
  grep -Fq '"portctl_visible_count"' ${source}/portctl/widget.luau
  grep -Fq 'noctalia.togglePanel("rxtsel/portctl:panel")' ${source}/portctl/widget.luau
  grep -Fq 'barWidget.setGlyph(current.glyph)' ${source}/mango_layouts/widget.luau
  grep -Fq 'noctalia.togglePanel("ezequiel/mango_layouts:panel")' ${source}/mango_layouts/widget.luau

  cp ${../resources/noctalia-community/mango_layouts/translations/zh-CN.json} \
    "$out/mango_layouts/translations/zh-CN.json"
  # These compact bar labels intentionally replace upstream rendering while
  # retaining each plugin's state source and click behavior. Fail on drift.
  cp ${../resources/noctalia-community/portctl/widget.luau} "$out/portctl/widget.luau"
  cp ${../resources/noctalia-community/portctl/count_label.luau} "$out/portctl/count_label.luau"
  cp ${../resources/noctalia-community/portctl/tests/count_label_test.luau} \
    "$out/portctl/tests/count_label_test.luau"
  luau "$out/portctl/tests/count_label_test.luau"
  grep -Fq 'local countLabel = require("./count_label.luau")' "$out/portctl/widget.luau"
  grep -Fq 'barWidget.setText(countLabel.format(count))' "$out/portctl/widget.luau"

  cp ${../resources/noctalia-community/mini-docker/widget.luau} "$out/mini-docker/widget.luau"
  cp ${../resources/noctalia-community/mini-docker/count_visibility.luau} \
    "$out/mini-docker/count_visibility.luau"
  cp ${../resources/noctalia-community/mini-docker/tests/count_visibility_test.luau} \
    "$out/mini-docker/tests/count_visibility_test.luau"
  luau "$out/mini-docker/tests/count_visibility_test.luau"
  grep -Fq 'countVisibility.shouldShow(showCountSetting, runningCount)' \
    "$out/mini-docker/widget.luau"

  cp ${../resources/noctalia-community/mango_layouts/widget.luau} "$out/mango_layouts/widget.luau"
  grep -Fq 'barWidget.setGlyphColor("secondary", "script")' "$out/mango_layouts/widget.luau"
''
