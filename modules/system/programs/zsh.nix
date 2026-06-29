_:

{
  programs.zsh.enable = true;

  # Replaced by nix-index (Home Manager). The default handler uses a stale
  # database and would otherwise override nix-index's shell hook.
  programs.command-not-found.enable = false;
}
