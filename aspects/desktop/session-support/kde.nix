{ palette }:
{ lib, ... }:
let
  rgb =
    color:
    lib.concatMapStringsSep ","
      (offset: toString (lib.fromHexString (builtins.substring offset 2 color)))
      [
        1
        3
        5
      ];
  colors = background: {
    BackgroundNormal = rgb background;
    BackgroundAlternate = rgb palette.surface;
    ForegroundNormal = rgb palette.brightFg;
    ForegroundInactive = rgb palette.fg;
    ForegroundActive = rgb palette.blue;
    ForegroundLink = rgb palette.blue;
    ForegroundVisited = rgb palette.purple;
    ForegroundNegative = rgb palette.red;
    ForegroundNeutral = rgb palette.yellow;
    ForegroundPositive = rgb palette.green;
    DecorationFocus = rgb palette.blue;
    DecorationHover = rgb palette.selection;
  };
  scheme = {
    "Colors:Window" = colors palette.bg;
    "Colors:View" = colors palette.deep;
    "Colors:Button" = colors palette.surface;
    "Colors:Selection" = colors palette.selection;
    "Colors:Tooltip" = colors palette.surface;
    "Colors:Complementary" = colors palette.deep;
    "Colors:Header" = colors palette.deep;
    "ColorEffects:Inactive".Enable = false;
    "ColorEffects:Disabled" = {
      Enable = true;
      Color = rgb palette.bg;
      ColorEffect = 0;
      ContrastEffect = 1;
      ContrastAmount = 0.5;
      IntensityEffect = 0;
    };
    General = {
      Name = "One Dark";
      ColorScheme = "NixDotfilesOneDark";
      shadeSortColumn = true;
    };
  };
in
{
  # KDE's KColorScheme can replace QApplication's qt6ct palette. Give it the
  # same source colors; HM is the sole writer of both of these static files.
  xdg.configFile.kdeglobals.text = lib.generators.toINI { } (
    scheme
    // {
      Icons.Theme = palette.iconTheme;
      KDE = {
        widgetStyle = "Fusion";
        ShowIconsInMenuItems = true;
        ShowIconsOnPushButtons = true;
      };
    }
  );
  xdg.dataFile."color-schemes/NixDotfilesOneDark.colors".text = lib.generators.toINI { } scheme;
}
