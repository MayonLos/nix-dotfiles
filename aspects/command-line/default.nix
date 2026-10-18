{ den, ... }: {
  imports = [ ../appearance ];
  den.aspects = {
    command-line = { host, user, ... }: {
      noctaliaIntegrations = [ "btop" ];
      homeManager.imports = [
        ({ pkgs, ... }: { home.packages = [ (import ./task-package.nix { inherit pkgs; }) ]; })
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
