{ den, ... }: {
  den.aspects = {
    command-line = { host, ... }: {
      homeManager.imports = [
        ./zsh.nix
        ./git.nix
        ./direnv.nix
        ./nix-index.nix
        ./tmux.nix
        ./yazi.nix
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
