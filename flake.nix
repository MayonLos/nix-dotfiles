{
  description = "NixOS from Scratch";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Neovim. The config itself lives in ./nixvim (repo root, *not* under
    # modules/ — lib/import-dir.nix recurses through every .nix file there and
    # would try to load each nixvim module as a Home Manager one). Built in
    # modules/home/programs/dev/nvim.nix.
    nixvim = {
      url = "github:nix-community/nixvim/nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    # The MCP server binary config/plugins/ai/mcphub.nix points mcphub.nvim at.
    # Not in nixpkgs.
    mcp-hub = {
      url = "github:ravitemer/mcp-hub";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Noctalia plugin repositories, consumed as plain source trees rather than
    # through noctalia's own git fetcher. A `kind = "path"` plugin source points
    # straight at the store path, so nothing is cloned at startup — see the
    # comment on settings.plugins in modules/home/wm/niri/noctalia.nix.
    noctalia-plugins-official = {
      url = "github:noctalia-dev/official-plugins";
      flake = false;
    };
    noctalia-plugins-community = {
      url = "github:noctalia-dev/community-plugins";
      flake = false;
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

    # Wayland screenshot tools, neither in nixpkgs. Both build from source with
    # no cachix, so deliberately NOT `follows`-ed — same reasoning as
    # noctalia-greeter: let them build against their own tested nixpkgs rather
    # than risk attr/version drift breaking the build.
    mark-shot.url = "github:jswysnemc/mark-shot";
    wayscrollshot.url = "github:jswysnemc/wayscrollshot";

    claude-code.url = "github:sadjow/claude-code-nix/v2";

    # Codex CLI. Same maintainer and same shape as claude-code above: prebuilt
    # binaries from upstream's own releases, refreshed hourly by CI, so it runs
    # ahead of nixpkgs (0.149 vs nixpkgs-unstable's 0.147 on 2026-08-22). Left
    # un-`follows`-ed for the same reason as claude-code — it ships a static
    # musl binary and only wants nixpkgs for the wrapper around it.
    codex-cli.url = "github:sadjow/codex-cli-nix";

    # Daily-updated packages for AI coding agents that nixpkgs does not carry
    # (dsh, zcode, ...). Deliberately NOT `follows`-ed: upstream only builds and
    # caches against its own pinned nixpkgs-unstable, and pointing it at this
    # flake's stable `nixpkgs` would both break eventually and miss every
    # prebuilt binary. The cost is one extra nixpkgs evaluation; the payoff is
    # cache.numtide.com hits, wired up in modules/system/core/nix.nix.
    llm-agents.url = "github:numtide/llm-agents.nix";

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
