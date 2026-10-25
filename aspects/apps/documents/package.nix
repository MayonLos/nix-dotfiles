{ pkgs }:

let
  onlyoffice = pkgs.onlyoffice-desktopeditors;
in
pkgs.symlinkJoin {
  name = "${onlyoffice.pname}-${onlyoffice.version}-xdg-portal";
  inherit (onlyoffice) pname version;
  paths = [ onlyoffice ];
  nativeBuildInputs = [ pkgs.makeWrapper ];

  postBuild = ''
    desktop="$out/share/applications/onlyoffice-desktopeditors.desktop"
    rm "$desktop"
    cp "${onlyoffice}/share/applications/onlyoffice-desktopeditors.desktop" "$desktop"
    chmod u+w "$desktop"
    substituteInPlace "$desktop" \
      --replace-fail "${onlyoffice}/bin/onlyoffice-desktopeditors " \
        "$out/bin/onlyoffice-desktopeditors --xdg-desktop-portal=default "

    rm "$out/bin/onlyoffice-desktopeditors"
    makeWrapper "${onlyoffice}/bin/onlyoffice-desktopeditors" "$out/bin/onlyoffice-desktopeditors" \
      --add-flags --xdg-desktop-portal=default
  '';

  passthru = {
    inherit (onlyoffice) pname version;
  };
}
