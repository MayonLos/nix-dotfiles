{
  description = "NixOS from Scratch";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    MyNixvim = {
      url = "github:MayonLos/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Graphical greetd login matching the Noctalia desktop. Separate repo from the
    # shell, single `nixpkgs` input pinned to nixos-unstable. Deliberately NOT
    # `follows`-ed — the greeter builds from source (no cachix), so we let it build
    # against its own tested nixpkgs to avoid attr/version drift breaking the build.
    noctalia-greeter.url = "github:noctalia-dev/noctalia-greeter";

    # Zen browser (not in nixpkgs). Provides a home-manager module (firefox-style
    # profiles). follows nixpkgs-unstable to dedup the heavy input; home-manager is
    # left on the flake's own pin so its mkFirefoxModule stays version-matched.
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    claude-code.url = "github:sadjow/claude-code-nix/v2";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Weekly-updated prebuilt nix-index database, so we never run `nix-index`
    # manually. Provides the command-not-found handler + `nix-locate` + comma.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      imports = [
        ./flake/system.nix
        ./flake/dev.nix
        inputs.home-manager.flakeModules.home-manager
        inputs.treefmt-nix.flakeModule
      ];
      perSystem =
        { system, ... }:
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        };
    };
}
