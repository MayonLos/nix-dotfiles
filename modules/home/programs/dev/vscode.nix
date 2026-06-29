{ pkgs, lib, ... }:
let
  vscode = pkgs.vscode.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/code \
        --suffix LD_LIBRARY_PATH : "${
          lib.makeLibraryPath [
            pkgs.stdenv.cc.cc.lib
            pkgs.libusb1
          ]
        }"
    '';
  });
in
{
  programs.vscode = {
    enable = true;
    package = vscode;
  };
}
