_: {
  imports = [ ../appearance ];
  den.aspects.documents = { user, ... }: {
    noctaliaIntegrations = [
      "obsidian"
      "zathura"
    ];
    homeManager = { pkgs, ... }: {
      imports = [
        (import ./zathura.nix { palette = user.appearance; })
        ./typora-theme.nix
      ];
      xdg.mimeApps = {
        enable = true;
        associations.added."application/pdf" = [ "org.kde.okular.desktop" ];
        defaultApplications."application/pdf" = [ "org.pwmt.zathura-pdf-mupdf.desktop" ];
      };
      home.packages = with pkgs; [
        typora
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
