{ pkgs, ... }:
{
  home.packages = with pkgs; [
    (pkgs.st.overrideAttrs (old: {
      src = ./config/st;
      patches = [ ];
      buildInputs =
        (old.buildInputs or [ ])
        ++ (with pkgs.xorg; [
          libXcursor
        ]);
    }))
    (pkgs.dmenu.overrideAttrs (_: {
      src = ./config/dmenu;
      patches = [ ];
    }))
    (pkgs.slstatus.overrideAttrs (_: {
      src = ./config/slstatus;
      patches = [ ];
    }))
  ];
}
