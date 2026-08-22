{
  pkgs,
  ...
}:

{
  # texlab lives in toolchain.nix. texliveFull stays here: Emacs (AUCTeX +
  # pdf-tools) and the CLI both compile documents with it, and it is the one
  # genuinely large thing in this config at ~5.9 GiB.
  home.packages = with pkgs; [
    texliveFull
  ];
}
