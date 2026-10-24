{ den, ... }: {
  imports = [
    ../../desktop/mango-session
    ../../appearance/appearance
    ../../workspace/workspace-task
  ];
  den.schema.user.imports = [ ./contract.nix ];
  den.aspects = {
    tree-account-tool.user = { pkgs, ... }: { packages = [ pkgs.tree ]; };
    command-line = { host, user, ... }: {
      noctaliaIntegrations = [ "btop" ];
      includes = [ den.aspects.workspace-task ];
      homeManager.imports = [
        (import ./zsh.nix {
          palette = user.appearance;
          inherit (user) secretExports;
        })
        (import ./git.nix { palette = user.appearance; })
        ./direnv.nix
        ./nix-index.nix
        ./tmux.nix
        (import ./yazi.nix { palette = user.appearance; })
        (import ./sysinfo.nix { palette = user.appearance; })
        (import ./tools.nix { palette = user.appearance; })
      ];
      user = { pkgs, ... }: { shell = pkgs.zsh; };
      provides.${host.name}.includes = [ den.aspects.command-line-host ];
    };
    command-line-host.nixos.imports = [ ./host.nix ];
  };
}
