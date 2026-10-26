{ inputs, ... }: {
  imports = [
    ../../desktop/mango-session
    ../../appearance/appearance
  ];
  den.aspects.documents = { user, ... }: {
    homeManager =
      {
        pkgs,
        lib,
        config,
        ...
      }:
      let
        hasPalette = user.appearance != null;
        templates =
          if hasPalette then
            import ./templates.nix {
              inherit pkgs;
              palette = user.appearance;
            }
          else
            { };
      in
      {
        imports = [
          inputs.noctalia.homeModules.default
          (import ./zathura.nix { palette = user.appearance; })
        ];
        programs.noctalia.settings.theme.templates.user =
          lib.mkIf (config.programs.noctalia.enable && hasPalette)
            {
              documents-zathura = {
                input_path = templates.zathura;
                output_path = "$XDG_CONFIG_HOME/zathura/noctaliarc";
              };
              documents-obsidian = {
                input_path = templates.obsidian;
                output_path_dynamic = "${pkgs.python3}/bin/python ${./resources/obsidian_theme.py} outputs";
                post_hook = "${pkgs.python3}/bin/python ${./resources/obsidian_theme.py} enable";
                hook_async = false;
              };
            };
        xdg.mimeApps = {
          enable = true;
          associations.added = {
            "application/msword" = [
              "writer.desktop"
            ];
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = [
              "writer.desktop"
            ];
            "application/vnd.ms-excel" = [
              "calc.desktop"
            ];
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = [
              "calc.desktop"
            ];
            "application/vnd.ms-powerpoint" = [
              "impress.desktop"
            ];
            "application/vnd.openxmlformats-officedocument.presentationml.presentation" = [
              "impress.desktop"
            ];
            "application/vnd.oasis.opendocument.text" = [
              "writer.desktop"
            ];
            "application/vnd.oasis.opendocument.spreadsheet" = [
              "calc.desktop"
            ];
            "application/vnd.oasis.opendocument.presentation" = [
              "impress.desktop"
            ];
          };
          defaultApplications = {
            "application/pdf" = [ "org.pwmt.zathura-pdf-mupdf.desktop" ];
            "application/msword" = [ "writer.desktop" ];
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = [
              "writer.desktop"
            ];
            "application/vnd.ms-excel" = [ "calc.desktop" ];
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = [
              "calc.desktop"
            ];
            "application/vnd.ms-powerpoint" = [ "impress.desktop" ];
            "application/vnd.openxmlformats-officedocument.presentationml.presentation" = [
              "impress.desktop"
            ];
            "application/vnd.oasis.opendocument.text" = [ "writer.desktop" ];
            "application/vnd.oasis.opendocument.spreadsheet" = [ "calc.desktop" ];
            "application/vnd.oasis.opendocument.presentation" = [ "impress.desktop" ];
            # Documents owns this narrow exception to the generic text editor
            # binding: Markdown opens in the installed document application.
            # force: The documents selection overrides the generic text MIME default for Markdown.
            "text/markdown" = lib.mkForce [ "obsidian.desktop" ];
          };
        };
        home.packages = with pkgs; [
          obsidian
          zotero
          # The Qt-enabled package can still auto-select GTK under Mango.
          # Prefer its native Qt6 UI without changing any personal LO settings;
          # explicit SAL_USE_VCLPLUGIN overrides remain available for diagnosis.
          (libreoffice-qt.override {
            extraMakeWrapperArgs = [
              "--set-default"
              "SAL_USE_VCLPLUGIN"
              "qt6"
            ];
          })
          hunspell
          hunspellDicts.en_US
          hyphenDicts.en_US
        ];
      };
  };
}
