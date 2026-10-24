{ host, user }:
{
  config,
  hostFacts,
  lib,
  pkgs,
  ...
}:
let
  avatar = import ./package.nix {
    inherit pkgs;
    name = user.avatar.name;
    initial = user.avatar.initial;
    palette = user.appearance;
  };
  faceSource = "${config.xdg.dataHome}/nix-dotfiles/${user.avatar.name}-avatar.png";
in
{
  # Use a stable managed target: future generations refresh the PNG
  # without guessing ownership from an existing file's store basename.
  xdg.dataFile."nix-dotfiles/${user.avatar.name}-avatar.png".source = avatar;
  home.activation.seedMayonAvatar = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    face="$HOME/.face"
    if [ ! -e "$face" ] && [ ! -L "$face" ]; then
      run ln -s ${lib.escapeShellArg faceSource} "$face"
    fi
  '';

}
