{ ... }: {
  den.quirks.editorLanguages.description = "Contributions from explicitly selected language aspects";
  imports = [
    ./cpp.nix
    ./support.nix
  ];
}
