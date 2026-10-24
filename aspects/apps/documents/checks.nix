{
  pkgs,
  home,
  appearance,
  ...
}:
let
  templates = home.programs.noctalia.settings.theme.templates.user;
  zathura = templates.documents-zathura.input_path;
  obsidian = templates.documents-obsidian.input_path;
  python = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.tinycss2 ]);
  paletteColors = builtins.filter (
    value: builtins.isString value && builtins.substring 0 1 value == "#"
  ) (builtins.attrValues appearance);
in
{
  documents-visual-config =
    pkgs.runCommand "documents-visual-config-check"
      {
        nativeBuildInputs = [ python ];
      }
      ''
        export PYTHONDONTWRITEBYTECODE=1
        ${python}/bin/python ${./resources}/test_obsidian_theme.py
        ${python}/bin/python - ${zathura} ${obsidian} '${builtins.toJSON paletteColors}' <<'PY'
        import json
        import re
        import shlex
        import sys
        from pathlib import Path

        import tinycss2

        zathura = Path(sys.argv[1]).read_text(encoding="utf-8")
        css = Path(sys.argv[2]).read_text(encoding="utf-8")
        palette_colors = set(json.loads(sys.argv[3]))
        expected_zathura = {
            "default-bg", "default-fg", "recolor-lightcolor", "recolor-darkcolor",
            "statusbar-bg", "statusbar-fg", "inputbar-bg", "inputbar-fg",
            "notification-bg", "notification-fg", "notification-error-bg",
            "notification-error-fg", "notification-warning-bg", "notification-warning-fg",
            "index-bg", "index-fg", "index-active-bg", "index-active-fg",
            "highlight-color", "highlight-active-color", "highlight-fg",
            "completion-bg", "completion-fg", "completion-group-bg", "completion-group-fg",
            "completion-highlight-fg", "completion-highlight-bg",
        }
        keys = set()
        for line_number, line in enumerate(zathura.splitlines(), start=1):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            tokens = shlex.split(line)
            assert len(tokens) == 3 and tokens[0] == "set", (line_number, line)
            keys.add(tokens[1])
            assert tokens[2].startswith("#") and len(tokens[2]) == 7, (line_number, line)
        assert keys == expected_zathura, (keys, expected_zathura)

        rules = tinycss2.parse_stylesheet(css, skip_comments=True, skip_whitespace=True)
        errors = [rule for rule in rules if rule.type == "error"]
        assert not errors, errors
        for rule in rules:
            if rule.type != "qualified-rule":
                continue
            declarations = tinycss2.parse_declaration_list(
                rule.content, skip_comments=True, skip_whitespace=True
            )
            errors = [declaration for declaration in declarations if declaration.type == "error"]
            assert not errors, (tinycss2.serialize(rule.prelude), errors)

        generated_colors = set(re.findall(r"#[0-9a-fA-F]{6}", zathura + css))
        assert generated_colors <= palette_colors, (generated_colors - palette_colors)
        PY
        touch "$out"
      '';
}
