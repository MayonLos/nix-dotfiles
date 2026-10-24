{ inputs, config, ... }: {
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      nixos = config.flake.nixosConfigurations.nixos-btw.config;
      home = nixos.home-manager.users.mayon;
      appearance = import ../aspects/appearance/appearance/onedark-darker.nix;
      args = {
        inherit
          pkgs
          lib
          system
          nixos
          home
          appearance
          ;
      };
      # Public feature hooks, explicitly registered. No module discovery.
      registry = [
        ../aspects/apps/firefox/checks.nix
        ../aspects/apps/documents/checks.nix
        ../aspects/cli/shell/checks.nix
        ../aspects/desktop/mango-session/checks.nix
        ../aspects/desktop/session-support/checks.nix
        ../aspects/desktop/xorg-session/checks.nix
        ../aspects/dev/embedded/checks.nix
        ../aspects/dev/neovim/checks.nix
        ../aspects/workspace/project-workbench/checks.nix
      ];
      featureChecks = builtins.foldl' (acc: path: acc // import path args) { } registry;
      embedded = import ../tests/composition/embedded.nix { inherit inputs pkgs; };
      # Evaluate only registrations here, never instantiate another host.
      registrations =
        (inputs.flake-parts.lib.evalFlakeModule { inherit inputs; } {
          imports = [
            inputs.den.flakeModule
            ../aspects
          ];
        }).config.den.aspects;
      architecture = import ../tests/architecture {
        inherit lib;
        root = ../.;
        unstableNames = builtins.attrNames pkgs.unstable;
        # Pipeline inspection derives the whitelist from the actual overlay.
        unstableInspectors = [ "nix/checks.nix" ];
        evaluatedAspectIds = builtins.attrNames registrations;
        publicFiles = [
          "aspects/appearance/appearance/onedark-darker.nix"
          "aspects/appearance/appearance/ansi.nix"
          "aspects/appearance/appearance/resources/wallpaper"
          "aspects/dev/neovim/package.nix"
          "aspects/desktop/xorg-session/dwm/package.nix"
        ]
        ++ map (path: lib.removePrefix "${toString ../.}/" (toString path)) registry;
      };
      source = builtins.path {
        path = ../.;
        name = "treefmt-source";
        filter =
          path: _:
          let
            name = builtins.baseNameOf path;
          in
          !(builtins.elem name [
            ".git"
            ".work"
            ".team"
            ".worktrees"
          ])
          && !(lib.hasPrefix "result" name);
      };
    in
    {
      treefmt.projectRoot = source;
      # Force during evaluation: flake check --no-build must reject violations.
      checks = builtins.deepSeq architecture (
        featureChecks
        // {
          architecture = pkgs.runCommand "architecture-check" { } "touch $out";
          statix = pkgs.runCommand "statix-check" { nativeBuildInputs = [ pkgs.statix ]; } ''
            statix check ${source}
            touch "$out"
          '';
          deadnix = pkgs.runCommand "deadnix-check" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
            deadnix --fail --no-lambda-pattern-names ${source}
            touch "$out"
          '';
          protocols-composition = import ../tests/composition/protocols.nix { inherit inputs pkgs; };
          remote-workspace-composition = import ../tests/composition/remote.nix { inherit inputs pkgs; };
          embedded-composition = embedded.composition;
          embedded-home = embedded.home;
          local-services-composition = import ../tests/composition/local-services.nix {
            inherit inputs pkgs;
          };
          desktop-composition = import ../tests/composition/desktop.nix { inherit inputs pkgs; };
          editing-composition = import ../tests/composition/editing.nix { inherit inputs pkgs; };
          workspace-composition = import ../tests/composition/workspace.nix { inherit inputs pkgs; };
          system-boundaries = import ../tests/composition/system.nix {
            inherit inputs pkgs;
            host = nixos;
          };
        }
      );
    };
}
