{ tools }:
{
  pkgs,
  lib,
  ...
}:
let
  makeWrapper =
    name: spec:
    pkgs.writeShellScriptBin name ''
      exec ${lib.escapeShellArgs spec.argv} "$@"
    '';

  selected = {
    terminal = if tools.terminal == null then null else makeWrapper "workspace-terminal" tools.terminal;
    editor = if tools.editor == null then null else makeWrapper "workspace-editor" tools.editor;
    browser = if tools.browser == null then null else makeWrapper "workspace-browser" tools.browser;
    fileManager =
      if tools.fileManager == null then null else makeWrapper "workspace-files" tools.fileManager;
  };

  pathOf = name: wrapper: "${wrapper}/bin/${name}";
  mimeDefaults = lib.filterAttrs (_: value: value != null) {
    "text/html" = if tools.browser == null then null else tools.browser.desktopId or null;
    "x-scheme-handler/http" = if tools.browser == null then null else tools.browser.desktopId or null;
    "x-scheme-handler/https" = if tools.browser == null then null else tools.browser.desktopId or null;
    "inode/directory" = if tools.fileManager == null then null else tools.fileManager.desktopId or null;
    "text/plain" = tools.guiTextEditor;
    "text/markdown" = tools.guiTextEditor;
    "application/x-shellscript" = tools.guiTextEditor;
  };

  sharedVariables = lib.mkMerge [
    (lib.optionalAttrs (selected.terminal != null) {
      TERMINAL = pathOf "workspace-terminal" selected.terminal;
    })
    (lib.optionalAttrs (selected.editor != null) {
      EDITOR = pathOf "workspace-editor" selected.editor;
      VISUAL = pathOf "workspace-editor" selected.editor;
    })
    (lib.optionalAttrs (selected.browser != null) {
      BROWSER = pathOf "workspace-browser" selected.browser;
    })
  ];
in
{
  home.packages = builtins.filter (value: value != null) (builtins.attrValues selected);

  home.sessionVariables = sharedVariables;
  systemd.user.sessionVariables = sharedVariables;

  xdg.mimeApps = lib.mkIf (mimeDefaults != { }) {
    enable = true;
    defaultApplications = lib.mapAttrs (_: id: [ id ]) mimeDefaults;
  };
}
