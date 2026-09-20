{ pkgs, config, ... }:
{
  # MATLAB's desktop comes up light. Its theme setting is
  # s.matlab.appearance.MATLABTheme, whose factory value is "System" -- but on
  # Linux that does not mean the desktop's preference: no MATLAB library
  # mentions org.freedesktop.appearance, so nothing here reads the portal, which
  # does report prefer-dark (checked with gdbus: uint32 1). "System" therefore
  # resolves to light and stays there.
  #
  # Setting it through `matlab -batch` does not stick -- measured, the mtime of
  # ~/.matlab/R2026a/matlab.mlsettings is unchanged afterwards, and a second
  # process reads System again. That file is an OPC zip archive in any case, so
  # it is not something Home Manager can own.
  #
  # startup.m is the declarative way in. MATLAB runs it from `userpath` on every
  # start, it is plain text, and TemporaryValue applies for the session without
  # writing to the settings archive at all. Verified by screenshotting a real
  # desktop under Xvfb: the editor, file browser and command window all come up
  # dark.
  #
  # This does NOT theme MATLAB's file dialogs, and nothing here can. Those are
  # Qt widgets drawn by the Qt 6.8.1 MATLAB bundles, which ships no
  # platformtheme plugin at all; nixpkgs' qt6ct is built against Qt 6.11.1 and
  # Qt refuses a plugin from a newer build. Tested both with
  # QT_QPA_PLATFORMTHEME=qt6ct inherited and with it unset -- the dialog is
  # light either way, so the variable is not what breaks it.
  home.file."Documents/MATLAB/startup.m".text = ''
    s = settings;
    s.matlab.appearance.MATLABTheme.TemporaryValue = 'Dark';
    clear s

    % Anything personal goes in startup-local.m beside this file, which Home
    % Manager does not own -- this one is a read-only symlink into the store.
    if exist(fullfile(userpath, 'startup-local.m'), 'file') == 2
      run(fullfile(userpath, 'startup-local.m'));
    end
  '';

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
