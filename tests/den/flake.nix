{
  description = "Isolated Den composition acceptance tests; no deployable hosts";

  inputs = {
    embedded-workbench = {
      url = "path:../../aspects/embedded-workbench";
      flake = false;
    };
    den.url = "github:denful/den/37eb88ce28a9e42d5b367b967a9097030ff4f665"; # v0.19.0
    nixpkgs.url = "github:NixOS/nixpkgs/7993f34ee47e28a3d607a525aadc6c94b73be728";
    home-manager = {
      url = "github:nix-community/home-manager/32904dfe1cf86039f3c8c9f41f94e1cfd76dbb34";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts/024633cd702b10285db5cb19b40ad48d2399ba60";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      system = "x86_64-linux";
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      evaluate =
        {
          choices ? [ ],
          conflictingSupport ? false,
          embeddedChoices ? [ ],
        }:
        (inputs.flake-parts.lib.mkFlake { inherit inputs; } {
          imports = [
            inputs.den.flakeModule
            (import ./fixture.nix { inherit choices conflictingSupport embeddedChoices; })
          ];
          systems = [ system ];
        }).nixosConfigurations;
      tests = import ./suite.nix {
        inherit evaluate;
        inherit (pkgs) lib;
      };
      embeddedTests = import ./embedded-suite.nix {
        inherit evaluate pkgs;
        inherit (pkgs) lib;
        stlinkRules = import "${inputs.embedded-workbench}/rules.nix" { inherit pkgs; };
      };
      embeddedHost = (evaluate { embeddedChoices = [ "alice@probe-a" ]; }).probe-a.config;
      embeddedProfile = embeddedHost.home-manager.users.alice.home.path;
      embeddedChecks = import "${inputs.embedded-workbench}/checks.nix" {
        inherit pkgs;
        profile = embeddedProfile;
        rules = embeddedHost.environment.etc."udev/rules.d".source;
      };
    in
    {
      lib.composition = tests;
      lib.embedded = embeddedTests;
      checks.${system} = {
        composition =
          assert tests.passed;
          pkgs.runCommand "den-composition" { } ''
            mkdir -p "$out"
            cp ${pkgs.writeText "den-composition.json" (builtins.toJSON tests.results)} "$out/results.json"
          '';
        # Build the actual selected Home Manager environment, without activation.
        shell-home =
          (evaluate { choices = [ "alice@probe-a" ]; })
          .probe-a.config.home-manager.users.alice.home.activationPackage;
        embedded-composition =
          assert embeddedTests.passed;
          pkgs.writeText "den-embedded-results.json" (builtins.toJSON embeddedTests.results);
        embedded-home = embeddedHost.home-manager.users.alice.home.activationPackage;
        embedded-udev = embeddedChecks.udev;
        embedded-tools = embeddedChecks.tools;
      };
    };
}
