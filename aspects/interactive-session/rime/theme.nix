{ pkgs, palette }:
let
  # Nine-slice SVG backgrounds follow catppuccin/fcitx5's rounded theme.
  # No compositor shadow is needed; the 1px outline keeps the panel distinct.
  svg =
    body:
    ''<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">${body}</svg>'';
  icon =
    body:
    ''<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">${body}</svg>'';
  margin = x: y: {
    Left = x;
    Right = x;
    Top = y;
    Bottom = y;
  };
  background = {
    Image = "panel.svg";
  };
  highlight = {
    Image = "highlight.svg";
  };
  conf = (pkgs.formats.ini { }).generate "theme.conf" {
    Metadata = {
      Name = "One-Dark-Darker";
      Version = 2;
      Author = "mayon";
      Description = "One Dark Darker rounded palette theme";
      ScaleWithDPI = "True";
    };
    InputPanel = {
      NormalColor = palette.brightFg;
      HighlightColor = palette.blue;
      HighlightCandidateColor = palette.blue;
      HighlightBackgroundColor = palette.selection;
      CandidateLabelColor = palette.muted;
      HighlightCandidateLabelColor = palette.muted;
      CandidateCommentColor = palette.muted;
      HighlightCandidateCommentColor = palette.muted;
      FullWidthHighlight = "False";
      PageButtonAlignment = "Bottom";
    };
    "InputPanel/Background" = background;
    "InputPanel/Background/Margin" = margin 12 12;
    "InputPanel/Highlight" = highlight;
    "InputPanel/Highlight/Margin" = margin 8 8;
    "InputPanel/ContentMargin" = margin 8 8;
    "InputPanel/TextMargin" = margin 12 8;
    "InputPanel/PrevPage".Image = "prev.svg";
    "InputPanel/PrevPage/ClickMargin" = margin 7 6;
    "InputPanel/NextPage".Image = "next.svg";
    "InputPanel/NextPage/ClickMargin" = margin 7 6;
    Menu = {
      NormalColor = palette.brightFg;
      HighlightCandidateColor = palette.blue;
      Spacing = 5;
    };
    "Menu/Background" = background;
    "Menu/Background/Margin" = margin 12 12;
    "Menu/Highlight" = highlight;
    "Menu/Highlight/Margin" = margin 8 8;
    "Menu/ContentMargin" = margin 8 8;
    "Menu/TextMargin" = margin 12 8;
    "Menu/Separator".Color = palette.border;
    "Menu/CheckBox".Image = "radio.svg";
    "Menu/SubMenu".Image = "arrow.svg";
  };
  images = {
    "panel.svg" =
      svg ''<rect x="0.5" y="0.5" width="47" height="47" rx="11.5" fill="${palette.bg}" stroke="${palette.border}"/>'';
    "highlight.svg" =
      svg ''<rect x="0.5" y="0.5" width="47" height="47" rx="7.5" fill="${palette.selection}" stroke="${palette.blue}" stroke-width="1"/>'';
    "prev.svg" =
      icon ''<path d="m12 4-6 6 6 6" fill="none" stroke="${palette.brightFg}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'';
    "next.svg" =
      icon ''<path d="m8 4 6 6-6 6" fill="none" stroke="${palette.brightFg}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'';
    "arrow.svg" =
      icon ''<path d="m8 4 6 6-6 6" fill="none" stroke="${palette.brightFg}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'';
    "radio.svg" =
      icon ''<circle cx="8" cy="8" r="5.5" fill="none" stroke="${palette.brightFg}"/><circle cx="8" cy="8" r="3" fill="${palette.blue}"/>'';
  };
in
pkgs.runCommand "fcitx5-onedark-darker-theme"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.librsvg
    ];
  }
  ''
    mkdir -p "$out"
    cp ${conf} "$out/theme.conf"
    ${pkgs.lib.concatStringsSep "\n" (
      pkgs.lib.mapAttrsToList (name: body: ''
        cp ${pkgs.writeText name body} "$out/${name}"
        rsvg-convert "$out/${name}" -o "$TMPDIR/${name}.png"
      '') images
    )}
    python3 - "$out" <<'PY'
    import configparser, pathlib, sys
    root = pathlib.Path(sys.argv[1])
    config = configparser.ConfigParser()
    config.read(root / "theme.conf")
    for section in config.values():
        if "image" in section:
            image = root / section["image"]
            assert image.is_file() and image.stat().st_size, image
    PY
  ''
