{ inputs, config, ... }: {
  perSystem =
    { pkgs, ... }:
    let
      embedded = import ../tests/composition/embedded.nix { inherit inputs pkgs; };
    in
    {
      # path:. includes a worktree's .git pointer file. treefmt's check creates
      # its own temporary Git repository; do not let that pointer redirect it
      # to the checkout outside the build sandbox. Keep untracked source files.
      treefmt.projectRoot = builtins.path {
        path = ../.;
        name = "treefmt-source";
        filter = path: _: builtins.baseNameOf path != ".git";
      };
      checks.project-workbench = import ../aspects/project-workbench/checks.nix { inherit pkgs; };
      checks.protocols-composition = import ../tests/composition/protocols.nix { inherit inputs pkgs; };
      checks.remote-workspace-composition = import ../tests/composition/remote.nix {
        inherit inputs pkgs;
      };
      checks.embedded-composition = embedded.composition;
      checks.embedded-home = embedded.home;
      checks.embedded-udev = embedded.udev;
      checks.embedded-tools = embedded.tools;
      checks.local-services-composition = import ../tests/composition/local-services.nix {
        inherit inputs pkgs;
      };
      checks.desktop-composition = import ../tests/composition/desktop.nix { inherit inputs pkgs; };
      checks.interactive-session-config = import ../aspects/interactive-session/checks.nix {
        inherit pkgs;
        host = config.flake.nixosConfigurations.nixos-btw.config;
        home = config.flake.nixosConfigurations.nixos-btw.config.home-manager.users.mayon;
        palette = import ../aspects/appearance/onedark-darker.nix;
      };
      checks.rime-technical-runtime = import ../aspects/interactive-session/rime-checks.nix {
        inherit pkgs;
        home = config.flake.nixosConfigurations.nixos-btw.config.home-manager.users.mayon;
      };
      checks.xorg-session-runtime = import ../aspects/interactive-session/xorg/checks.nix {
        inherit pkgs;
        host = config.flake.nixosConfigurations.nixos-btw.config;
        home = config.flake.nixosConfigurations.nixos-btw.config.home-manager.users.mayon;
      };
      checks.editing-composition = import ../tests/composition/editing.nix { inherit inputs pkgs; };
      checks.workspace-composition = import ../tests/composition/workspace.nix { inherit inputs pkgs; };
      checks.command-line-runtime = import ../aspects/command-line/checks.nix {
        inherit pkgs;
        systemPath = config.flake.nixosConfigurations.nixos-btw.config.system.path;
        home = config.flake.nixosConfigurations.nixos-btw.config.home-manager.users.mayon;
        palette = import ../aspects/appearance/onedark-darker.nix;
      };
      checks.system-boundaries = import ../tests/composition/system.nix {
        inherit inputs pkgs;
        host = config.flake.nixosConfigurations.nixos-btw.config;
      };
    };
}
