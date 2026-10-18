{ inputs, config, ... }: {
  perSystem = { pkgs, ... }: {
    checks.workspace-composition = import ../tests/composition/workspace.nix { inherit inputs pkgs; };
    checks.command-line-runtime = import ../aspects/command-line/checks.nix {
      inherit pkgs;
      systemPath = config.flake.nixosConfigurations.nixos-btw.config.system.path;
      home = config.flake.nixosConfigurations.nixos-btw.config.home-manager.users.mayon;
      palette = import ../aspects/appearance/onedark-darker.nix;
    };
    checks.system-boundaries = import ../tests/composition/system.nix { inherit inputs pkgs; };
  };
}
