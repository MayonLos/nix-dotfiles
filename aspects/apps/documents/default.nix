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
          associations.added."application/pdf" = [ "org.kde.okular.desktop" ];
          defaultApplications = {
            "application/pdf" = [ "org.pwmt.zathura-pdf-mupdf.desktop" ];
            # Documents owns this narrow exception to the generic text editor
            # binding: Markdown opens in the installed document application.
            # force: The documents selection overrides the generic text MIME default for Markdown.
            "text/markdown" = lib.mkForce [ "obsidian.desktop" ];
          };
        };
        home.packages = with pkgs; [
          obsidian
          zotero
          kdePackages.okular
          libreoffice-qt
          hunspell
          hunspellDicts.en_US
          hyphenDicts.en_US
        ];
      };
  };
}
