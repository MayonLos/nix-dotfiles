{ pkgs, palette }:
let
  inherit (pkgs) lib;
  # Compact underlined candidate selection: a surface panel with a hairline
  # edge and soft shadow, with no selected-row fill.
  hex = c: lib.fromHexString (lib.removePrefix "#" c);
  channel = c: shift: lib.mod (builtins.div (hex c) shift) 256;
  mix =
    a: b: t:
    let
      ch =
        shift:
        let
          v = builtins.floor ((channel a shift) * (1 - t) + (channel b shift) * t + 0.5);
          h = lib.toLower (lib.toHexString v);
        in
        if builtins.stringLength h == 1 then "0" + h else h;
    in
    "#" + ch 65536 + ch 256 + ch 1;
  edge = mix palette.deep palette.border 0.45;
  transparentBlack = palette.black + "00";

  # Shadow padding baked into panel.svg; ShadowMargin tells classicui which
  # part of the image is shadow rather than panel surface.
  shadow = {
    Left = 10;
    Right = 10;
    Top = 8;
    Bottom = 14;
  };
  radius = 10;
  pad = 6;
  addEach = n: m: lib.mapAttrs (_: v: v + n) m;
  margin = x: y: {
    Left = x;
    Right = x;
    Top = y;
    Bottom = y;
  };
  icon =
    body:
    ''<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">${body}</svg>'';
  chevron =
    d: color:
    icon ''<path d="${d}" fill="none" stroke="${color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>'';

  conf = (pkgs.formats.ini { }).generate "theme.conf" {
    Metadata = {
      Name = "onedark";
      Version = 3;
      Author = "mayon";
      Description = "One Dark refined: underlined selection, muted labels, drop shadow";
      ScaleWithDPI = "True";
    };
    InputPanel = {
      NormalColor = palette.fg;
      HighlightCandidateColor = palette.brightFg;
      HighlightColor = palette.brightFg;
      # Fcitx Color uses #RRGGBBAA; keep the fallback fill transparent.
      HighlightBackgroundColor = transparentBlack;
      CandidateLabelColor = palette.muted;
      HighlightCandidateLabelColor = palette.blue;
      CandidateCommentColor = palette.muted;
      HighlightCandidateCommentColor = palette.muted;
      FullWidthHighlight = "False";
      PageButtonAlignment = "Center";
    };
    "InputPanel/Background".Image = "panel.svg";
    # Nine-slice border = shadow padding + corner radius.
    "InputPanel/Background/Margin" = addEach radius shadow;
    "InputPanel/ShadowMargin" = shadow;
    "InputPanel/ContentMargin" = addEach pad shadow;
    "InputPanel/Highlight".Image = "highlight.svg";
    # Keep the 2px line in the fixed bottom slice and rounded caps in the
    # fixed side slices; the transparent centre stretches around the text.
    "InputPanel/Highlight/Margin" = {
      Left = 9;
      Right = 9;
      Top = 1;
      Bottom = 3;
    };
    "InputPanel/TextMargin" = margin 6 5;
    "InputPanel/PrevPage".Image = "prev.svg";
    "InputPanel/PrevPage/ClickMargin" = margin 6 6;
    "InputPanel/NextPage".Image = "next.svg";
    "InputPanel/NextPage/ClickMargin" = margin 6 6;
    Menu = {
      NormalColor = palette.fg;
      HighlightCandidateColor = palette.brightFg;
      Spacing = 2;
    };
    "Menu/Background".Image = "panel.svg";
    "Menu/Background/Margin" = addEach radius shadow;
    "Menu/ShadowMargin" = shadow;
    "Menu/ContentMargin" = addEach pad shadow;
    "Menu/Highlight".Image = "highlight.svg";
    "Menu/Highlight/Margin" = {
      Left = 9;
      Right = 9;
      Top = 1;
      Bottom = 3;
    };
    "Menu/TextMargin" = margin 6 6;
    "Menu/Separator".Color = edge;
    "Menu/CheckBox".Image = "radio.svg";
    "Menu/SubMenu".Image = "arrow.svg";
  };

  W = 64;
  H = 64;
  panelSvg = ''
    <svg xmlns="http://www.w3.org/2000/svg" width="${toString W}" height="${toString H}" viewBox="0 0 ${toString W} ${toString H}">
      <defs>
        <filter id="s" x="-40%" y="-40%" width="180%" height="180%">
          <feGaussianBlur in="SourceAlpha" stdDeviation="4.5"/>
          <feOffset dy="3" result="b"/>
          <feFlood flood-color="${palette.black}" flood-opacity="0.55" result="ink"/>
          <feComposite in="ink" in2="b" operator="in"/>
          <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
        </filter>
      </defs>
      <rect x="${toString shadow.Left}.5" y="${toString shadow.Top}.5"
            width="${toString (W - shadow.Left - shadow.Right - 1)}" height="${
              toString (H - shadow.Top - shadow.Bottom - 1)
            }"
            rx="${toString (radius - 0.5)}" fill="${palette.surface}" stroke="${edge}" filter="url(#s)"/>
    </svg>'';
  images = {
    "panel.svg" = panelSvg;
    "highlight.svg" =
      ''<svg xmlns="http://www.w3.org/2000/svg" width="32" height="16" viewBox="0 0 32 16"><rect x="8" y="13" width="16" height="2" rx="1" fill="${palette.blue}"/></svg>'';
    "prev.svg" = chevron "m12 4.5-5.5 5.5 5.5 5.5" palette.muted;
    "next.svg" = chevron "m8 4.5 5.5 5.5-5.5 5.5" palette.fg;
    "arrow.svg" = chevron "m8 4.5 5.5 5.5-5.5 5.5" palette.fg;
    "radio.svg" =
      icon ''<circle cx="10" cy="10" r="6" fill="none" stroke="${palette.fg}" stroke-width="1.5"/><circle cx="10" cy="10" r="3" fill="${palette.blue}"/>'';
  };
in
pkgs.runCommand "fcitx5-onedark-theme"
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
