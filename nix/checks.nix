{ inputs, config, ... }: {
  perSystem =
    { pkgs, ... }:
    let
      embedded = import ../tests/composition/embedded.nix { inherit inputs pkgs; };
    in
    {
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
      checks.editing-composition = import ../tests/composition/editing.nix { inherit inputs pkgs; };
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
