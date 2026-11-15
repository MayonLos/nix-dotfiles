{
  imports = [
    ../../desktop/mango-session
    ../../appearance/appearance
  ];
  den.aspects.documents = { user, ... }: {
    homeManager =
      {
        pkgs,
        lib,
        ...
      }:
      let
        hasPalette = user.appearance != null;
        templates =
          if hasPalette then
            import ./templates.nix {
              # The palette is consumed directly by zathura/obsidian; a missing
              # appearance leaves the stock application theme in place.
              inherit pkgs;
              palette = user.appearance;
            }
          else
            { };
      in
      {
        imports = [ (import ./zathura.nix { palette = user.appearance; }) ];
        # Both document themes are plain files rendered by Nix. Zathura reads a
        # seeded include file; Obsidian gets a managed snippet written into each
        # registered vault and enabled in its appearance.json.
        home.activation.seedObsidianTheme = lib.mkIf hasPalette (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            if [ -d "$XDG_CONFIG_HOME" ]; then
              run ${pkgs.python3}/bin/python ${./resources/obsidian_theme.py} install \
                ${lib.escapeShellArg "${templates.obsidian}"} \
                || echo "warning: could not write the Obsidian theme snippet" >&2
            fi
          ''
        );
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
