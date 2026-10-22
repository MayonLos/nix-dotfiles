{
  description = "Den-based NixOS and Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    den.url = "github:denful/den/37eb88ce28a9e42d5b367b967a9097030ff4f665"; # v0.19.0

    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Noctalia plugin repositories, consumed as plain source trees rather than
    # through noctalia's own git fetcher. A `kind = "path"` plugin source points
    # straight at the store path, so nothing is cloned at startup — see the
    # comment in aspects/interactive-session/noctalia/plugins.nix.
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

    # MangoWC: the compositor this host runs (aspects/interactive-session/host/mango.nix,
    # aspects/interactive-session/), a dwl derivative. It is in
    # nixpkgs-unstable, but the flake is what carries the home-manager module
    # that renders ~/.config/mango/config.conf from Nix, so we take the flake.
    #
    # Deliberately NOT `follows`-ed. mango pins its own `scenefx` against its
    # own nixpkgs-unstable, and mango/scenefx/wlroots are a version-tight
    # triple -- forcing this flake's stable nixpkgs on it is exactly the kind
    # of pairing that breaks on a channel bump. Unlike the other un-followed
    # inputs there is no binary cache to preserve here (mango publishes none),
    # but there is also nothing to lose: it is dwl-sized C and builds in
    # seconds.
    mango.url = "github:mangowm/mango";

    # Wayland screenshot tools, neither in nixpkgs. Both build from source with
    # no cachix, so deliberately NOT `follows`-ed — same reasoning as
    # noctalia-greeter: let them build against their own tested nixpkgs rather
    # than risk attr/version drift breaking the build.
    mark-shot.url = "github:jswysnemc/mark-shot";
    wayscrollshot.url = "github:jswysnemc/wayscrollshot";

    # Daily-updated packages for AI coding agents: codex, claude-code, dsh, grok
    # and the review/usage tooling around them. zcode is deliberately NOT
    # installed -- see aspects/ai-workbench/ai-agents.nix. Deliberately NOT
    # `follows`-ed: upstream only builds and caches against its own pinned
    # nixpkgs-unstable, and pointing it at this flake's stable `nixpkgs` would
    # both break eventually and miss every prebuilt binary. The cost is one
    # extra nixpkgs evaluation; the payoff is cache.numtide.com hits, wired up
    # in aspects/system/maintenance/nix.nix.
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

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } ./nix;
}
