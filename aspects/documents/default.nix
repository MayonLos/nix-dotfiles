_: {
  imports = [ ../appearance ];
  den.aspects.documents = { user, ... }: {
    noctaliaIntegrations = [
      "obsidian"
      "zathura"
    ];
    homeManager = { pkgs, lib, ... }: {
      imports = [
        (import ./zathura.nix { palette = user.appearance; })
      ];
      xdg.mimeApps = {
        enable = true;
        associations.added."application/pdf" = [ "org.kde.okular.desktop" ];
        defaultApplications = {
          "application/pdf" = [ "org.pwmt.zathura-pdf-mupdf.desktop" ];
          # Documents owns this narrow exception to the generic text editor
          # binding: Markdown opens in the installed document application.
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
