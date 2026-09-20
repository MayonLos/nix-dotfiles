{ pkgs, config, ... }:
{
  # No MATLAB theme is managed here, deliberately. A
  # home.file."Documents/MATLAB/startup.m" setting
  # s.matlab.appearance.MATLABTheme.TemporaryValue = 'Dark' was added on
  # 2026-09-20 and removed the same day on request: it did darken the desktop,
  # editor and command window (screenshotted under Xvfb), but not the file
  # dialogs, which was the part that mattered. Flip the theme in Preferences >
  # Appearance if you want it; it is one setting, and not worth a managed file.
  #
  # The dialogs cannot be themed from outside, and this is the measured version
  # of that claim, not a guess. They are Qt widgets drawn by the Qt 6.8.1
  # MATLAB bundles, which ships no platformtheme plugin. Four routes tested,
  # all light:
  #   - nixpkgs' qt6ct (Qt 6.11): Qt rejects it outright --
  #     "uses incompatible Qt library. (6.11.0)"
  #   - nixos-24.11's qt6ct 0.10 (Qt 6.8.3): *does* load into a MATLABWindow
  #     started by hand, yet /proc/<pid>/maps shows it absent when MATLAB
  #     spawns that same binary with the same environment
  #   - QT_QPA_PLATFORMTHEME unset: Qt falls back to QGenericUnixTheme, which
  #     never overrides colorScheme(), so the palette is always light. The
  #     portal strings in libQt6Gui belong to QGnomeTheme, not to that one
  #   - QT_QPA_PLATFORMTHEME=gnome, i.e. QGnomeTheme, which is built in and
  #     does read the portal (the portal reports prefer-dark, checked with
  #     gdbus): still light
  # Four different ways of reaching the platform theme, one result, which
  # points at MATLAB setting its own palette. Do not spend another evening on
  # it without new evidence.

  home.packages = [
    # Not callPackage: pkgs/matlab.nix needs the whole package set to build its
    # FHS target list, and the user's real home directory to find the install
    # tree. See the header comment there for why MATLAB itself cannot be a
    # derivation -- octave.nix covers the .m work that does not need it.
    (import ../../../../pkgs/matlab.nix {
      inherit pkgs;
      inherit (config.home) homeDirectory;
    })
  ];
}
