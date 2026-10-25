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
        onlyofficePackage = import ./package.nix { inherit pkgs; };
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
              "onlyoffice-desktopeditors.desktop"
              "writer.desktop"
            ];
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = [
              "onlyoffice-desktopeditors.desktop"
              "writer.desktop"
            ];
            "application/vnd.ms-excel" = [
              "onlyoffice-desktopeditors.desktop"
              "calc.desktop"
            ];
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = [
              "onlyoffice-desktopeditors.desktop"
              "calc.desktop"
            ];
            "application/vnd.ms-powerpoint" = [
              "onlyoffice-desktopeditors.desktop"
              "impress.desktop"
            ];
            "application/vnd.openxmlformats-officedocument.presentationml.presentation" = [
              "onlyoffice-desktopeditors.desktop"
              "impress.desktop"
            ];
            "application/vnd.oasis.opendocument.text" = [
              "onlyoffice-desktopeditors.desktop"
              "writer.desktop"
            ];
            "application/vnd.oasis.opendocument.spreadsheet" = [
              "onlyoffice-desktopeditors.desktop"
              "calc.desktop"
            ];
            "application/vnd.oasis.opendocument.presentation" = [
              "onlyoffice-desktopeditors.desktop"
              "impress.desktop"
            ];
          };
          defaultApplications = {
            "application/pdf" = [ "org.pwmt.zathura-pdf-mupdf.desktop" ];
            "application/msword" = [ "onlyoffice-desktopeditors.desktop" ];
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = [
              "onlyoffice-desktopeditors.desktop"
            ];
            "application/vnd.ms-excel" = [ "onlyoffice-desktopeditors.desktop" ];
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = [
              "onlyoffice-desktopeditors.desktop"
            ];
            "application/vnd.ms-powerpoint" = [ "onlyoffice-desktopeditors.desktop" ];
            "application/vnd.openxmlformats-officedocument.presentationml.presentation" = [
              "onlyoffice-desktopeditors.desktop"
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
        home.activation.seedOnlyOfficeDesktopTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${pkgs.python3}/bin/python ${./resources/seed-onlyoffice-config.py} "${config.xdg.configHome}/onlyoffice/DesktopEditors.conf"
        '';
        home.packages = with pkgs; [
          obsidian
          zotero
          libreoffice-qt
          onlyofficePackage
          hunspell
          hunspellDicts.en_US
          hyphenDicts.en_US
        ];
      };
  };
}
