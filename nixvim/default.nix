{
  version.enableNixpkgsReleaseCheck = false;
  imports = [
    ./core
    ./options.nix
    ./keymappings.nix
    ./autocmds.nix
    ./highlights.nix
    ./theme.nix
    ./plugins
    ./packages.nix
  ];
}
