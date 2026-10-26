{ pkgs, palette }:
let
  inherit (pkgs) lib;
  checkmark =
    stroke: name:
    pkgs.writeText name ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
        <path d="m3.2 8.2 3.1 3.1 6.5-6.6" fill="none" stroke="${stroke}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
    '';
  indeterminate =
    stroke: name:
    pkgs.writeText name ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
        <path d="M3.5 8h9" fill="none" stroke="${stroke}" stroke-width="2" stroke-linecap="round"/>
      </svg>
    '';
  checkedMark = checkmark palette.deep "one-dark-checkbox.svg";
  disabledMark = checkmark palette.fg "one-dark-checkbox-disabled.svg";
  indeterminateMark = indeterminate palette.fg "one-dark-checkbox-indeterminate.svg";
  disabledIndeterminateMark = indeterminate palette.muted "one-dark-checkbox-indeterminate-disabled.svg";
  themeManifest = pkgs.writeText "one-dark-prism-theme.json" (
    builtins.toJSON {
      name = "One Dark";
      widgets = "Fusion";
      qssFilePath = "themeStyle.qss";
      colors = {
        Window = palette.bg;
        WindowText = palette.brightFg;
        Base = palette.deep;
        AlternateBase = palette.surface;
        ToolTipBase = palette.surface;
        ToolTipText = palette.brightFg;
        Text = palette.brightFg;
        Button = palette.surface;
        ButtonText = palette.brightFg;
        BrightText = palette.brightFg;
        Link = palette.blue;
        Highlight = palette.selection;
        HighlightedText = palette.brightFg;
        fadeColor = palette.bg;
        fadeAmount = 0.5;
      };
    }
  );
  template = builtins.readFile ./resources/qt/one-dark.qss.template;
in
{
  inherit
    checkedMark
    disabledMark
    indeterminateMark
    disabledIndeterminateMark
    themeManifest
    ;
  stylesheet = pkgs.writeText "one-dark.qss" (
    lib.replaceStrings
      [
        "@BG@"
        "@DEEP@"
        "@SURFACE@"
        "@SELECTION@"
        "@FG@"
        "@BRIGHT_FG@"
        "@MUTED@"
        "@BORDER@"
        "@BLUE@"
        "@FONT_SANS@"
        "@FONT_MONO@"
        "@CHECKMARK@"
        "@CHECKMARK_DISABLED@"
        "@INDETERMINATE@"
        "@INDETERMINATE_DISABLED@"
      ]
      [
        palette.bg
        palette.deep
        palette.surface
        palette.selection
        palette.fg
        palette.brightFg
        palette.muted
        palette.border
        palette.blue
        palette.fonts.sans
        palette.fonts.mono
        (toString checkedMark)
        (toString disabledMark)
        (toString indeterminateMark)
        (toString disabledIndeterminateMark)
      ]
      template
  );
}
