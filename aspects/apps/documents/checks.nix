{
  lib,
  pkgs,
  home,
  appearance,
  ...
}:
let
  templates = home.programs.noctalia.settings.theme.templates.user;
  zathura = templates.documents-zathura.input_path;
  obsidian = templates.documents-obsidian.input_path;
  zathuraOptions = home.programs.zathura.options;
  python = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.tinycss2 ]);
  paletteColors = builtins.filter (
    value: builtins.isString value && builtins.substring 0 1 value == "#"
  ) (builtins.attrValues appearance);
  pdfApplications = home.xdg.mimeApps.defaultApplications."application/pdf" or [ ];
  okularInstalled = builtins.any (package: (package.pname or "") == "okular") home.home.packages;
  okularAssociated = lib.hasInfix "okular" (
    builtins.toJSON {
      inherit (home.xdg.mimeApps) defaultApplications associations;
    }
  );
  packageNames = map (package: package.pname or "") home.home.packages;
  officeDefaults = {
    "application/msword" = "writer.desktop";
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = "writer.desktop";
    "application/vnd.ms-excel" = "calc.desktop";
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = "calc.desktop";
    "application/vnd.ms-powerpoint" = "impress.desktop";
    "application/vnd.openxmlformats-officedocument.presentationml.presentation" = "impress.desktop";
    "application/vnd.oasis.opendocument.text" = "writer.desktop";
    "application/vnd.oasis.opendocument.spreadsheet" = "calc.desktop";
    "application/vnd.oasis.opendocument.presentation" = "impress.desktop";
  };
  officeAssociations = home.xdg.mimeApps.associations.added;
in
{
  documents-mime-config =
    assert pdfApplications == [ "org.pwmt.zathura-pdf-mupdf.desktop" ];
    assert !okularInstalled;
    assert !okularAssociated;
    assert !(builtins.elem "onlyoffice-desktopeditors" packageNames);
    assert builtins.elem "libreoffice" packageNames;
    assert lib.all (
      mime: (home.xdg.mimeApps.defaultApplications.${mime} or [ ]) == [ officeDefaults.${mime} ]
    ) (builtins.attrNames officeDefaults);
    assert lib.all (
      mime:
      let
        associations = officeAssociations.${mime} or [ ];
      in
      associations == [ officeDefaults.${mime} ]
    ) (builtins.attrNames officeDefaults);
    pkgs.runCommand "documents-mime-config-check" { } ''
      test '${builtins.head pdfApplications}' = org.pwmt.zathura-pdf-mupdf.desktop
      test '${
        officeDefaults."application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      }' = writer.desktop
      test '${officeDefaults."application/vnd.oasis.opendocument.text"}' = writer.desktop
      touch "$out"
    '';

  documents-visual-config =
    pkgs.runCommand "documents-visual-config-check"
      {
        nativeBuildInputs = [ python ];
      }
      ''
        export PYTHONDONTWRITEBYTECODE=1
        ${python}/bin/python ${./resources}/test_obsidian_theme.py
        ${python}/bin/python - ${zathura} ${obsidian} '${builtins.toJSON paletteColors}' '${builtins.toJSON zathuraOptions}' <<'PY'
        import json
        import re
        import shlex
        import sys
        from pathlib import Path

        import tinycss2

        zathura = Path(sys.argv[1]).read_text(encoding="utf-8")
        css = Path(sys.argv[2]).read_text(encoding="utf-8")
        palette_colors = set(json.loads(sys.argv[3]))
        zathura_options = json.loads(sys.argv[4])
        assert zathura_options["guioptions"] == "s"
        assert zathura_options["statusbar-page-percent"] is True
        assert zathura_options["statusbar-basename"] is False
        assert "Maple Mono NF CN" in zathura_options["font"]
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
