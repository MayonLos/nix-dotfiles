{ den, ... }: {
  imports = [
    ../appearance
    ../workspace-task
  ];
  den.aspects = {
    command-line = { host, user, ... }: {
      noctaliaIntegrations = [ "btop" ];
      includes = [ den.aspects.workspace-task ];
      homeManager.imports = [
        ./zsh.nix
        (import ./git.nix { palette = user.appearance; })
        ./direnv.nix
        ./nix-index.nix
        ./tmux.nix
        (import ./yazi.nix { palette = user.appearance; })
        ./sysinfo.nix
        ./tools.nix
      ];
      user = { pkgs, ... }: { shell = pkgs.zsh; };
      provides.${host.name}.includes = [ den.aspects.command-line-host ];
    };
    command-line-host.nixos.imports = [ ./host.nix ];
    terminal = { user, ... }: { homeManager = import ./kitty.nix { palette = user.appearance; }; };
  };
}
