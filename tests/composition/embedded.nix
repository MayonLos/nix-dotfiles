{ inputs, pkgs }:
let
  lib = inputs.nixpkgs.lib;
  system = "x86_64-linux";

  evaluate =
    {
      embedded ? [ ],
      commandLine ? [ ],
    }:
    (inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { den, ... }:
      {
        imports = [
          inputs.den.flakeModule
          ../../aspects/embedded-workbench
          ../../aspects/command-line
        ];

        den.systems = [ system ];
        den.schema.user.classes = [ "homeManager" ];

        den.hosts.${system} = {
          hostA.users = {
            alice = { };
            bob = { };
          };
          hostB.users = {
            alice = { };
            bob = { };
          };
        };

        den.default = {
          nixos = {
            system.stateVersion = "26.05";
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            home-manager.useGlobalPkgs = true;
            home-manager.extraSpecialArgs.inputs = inputs;
            nixpkgs.config.allowUnfree = true;
          };
          homeManager.home.stateVersion = "26.05";
        };

        den.aspects =
          lib.genAttrs
            [
              "alice@hostA"
              "bob@hostA"
              "alice@hostB"
              "bob@hostB"
            ]
            (
              binding:
              let
                username = builtins.head (lib.splitString "@" binding);
              in
              {
                user.isNormalUser = true;
                homeManager.home = {
                  inherit username;
                  homeDirectory = "/home/${username}";
                };
                includes =
                  lib.optionals (lib.elem binding embedded) [ den.aspects.embedded-workbench ]
                  ++ lib.optionals (lib.elem binding commandLine) [ den.aspects.command-line ];
              }
            );
      }
    )).nixosConfigurations;

  baseline = evaluate { };
  selected = evaluate { embedded = [ "alice@hostA" ]; };
  shared = evaluate {
    embedded = [
      "alice@hostA"
      "bob@hostA"
    ];
  };
  mirrored = evaluate { embedded = [ "bob@hostB" ]; };
  remaining = evaluate { embedded = [ "bob@hostA" ]; };
  combined = evaluate {
    embedded = [ "alice@hostA" ];
    commandLine = [ "alice@hostA" ];
  };
  afterLastConsumerRemoved = evaluate { };

  inspect =
    host:
    let
      inherit (host) config;
    in
    {
      rules = map toString config.services.udev.packages;
      accounts = lib.genAttrs [ "alice" "bob" ] (name: {
        groups = config.users.users.${name}.extraGroups;
        tools = map (
          package: package.pname or (lib.getName package)
        ) config.home-manager.users.${name}.home.packages;
      });
      graphical =
        config.services.xserver.enable
        || config.services.displayManager.enable
        || config.programs.sway.enable;
      shell = config.programs.zsh.enable;
    };

  baselineA = inspect baseline.hostA;
  selectedA = inspect selected.hostA;
  sharedA = inspect shared.hostA;
  mirroredB = inspect mirrored.hostB;
  remainingA = inspect remaining.hostA;
  combinedA = inspect combined.hostA;

  embeddedTools = [
    "gcc-arm-embedded"
    "openocd"
    "stlink"
    "probe-rs-tools"
    "dfu-util"
    "stm32flash"
    "stm32cubemx"
    "stm32cubeprogrammer"
    "tio"
    "cmake"
    "ninja"
    "pkg-config-wrapper"
    "gdb"
  ];
  hasTools = account: lib.all (name: lib.elem name account.tools) embeddedTools;
  noTools = account: !lib.any (name: lib.elem name account.tools) embeddedTools;
  additions = host: builtins.filter (path: !(lib.elem path baselineA.rules)) host.rules;
  selectedRules = additions selectedA;
  expectedRulePackages = map toString [
    pkgs.openocd
    (import ../../aspects/embedded-workbench/rules.nix { inherit pkgs; })
  ];
  groups = config: user: lib.sort builtins.lessThan config.users.users.${user}.extraGroups;
  hasRulePackages =
    host:
    builtins.all (
      package: lib.elem package (map toString host.config.services.udev.packages)
    ) expectedRulePackages;
  hasNoEmbeddedRules =
    host:
    builtins.all (
      package: !(lib.elem package (map toString host.config.services.udev.packages))
    ) expectedRulePackages;

  result = {
    unselectedHasNoToolsGroupsOrHostRules =
      noTools baselineA.accounts.alice
      && noTools baselineA.accounts.bob
      && baselineA.accounts.alice.groups == [ ]
      && baselineA.accounts.bob.groups == [ ]
      && hasNoEmbeddedRules baseline.hostA;

    selectedBindingGetsCompleteToolsAndRules =
      hasTools selectedA.accounts.alice
      && selectedA.accounts.alice.groups == [ "dialout" ]
      && lib.all (package: lib.elem package selectedRules) expectedRulePackages
      && hasRulePackages selected.hostA
      && builtins.length selectedRules == 3
      && !hasTools selectedA.accounts.bob
      && selectedA.accounts.bob.groups == [ ]
      && !hasTools (inspect selected.hostB).accounts.alice
      && hasNoEmbeddedRules selected.hostB;

    mirroredBindingSelectsOnlyItsHostAndUser =
      hasTools mirroredB.accounts.bob
      && mirroredB.accounts.bob.groups == [ "dialout" ]
      && !hasTools mirroredB.accounts.alice
      && mirroredB.accounts.alice.groups == [ ]
      && additions mirroredB == selectedRules
      && inspect mirrored.hostA == baselineA;

    sharedHostSupportIsDeduplicated =
      additions sharedA == selectedRules
      && builtins.length (lib.unique (additions sharedA)) == builtins.length (additions sharedA)
      && hasTools sharedA.accounts.alice
      && hasTools sharedA.accounts.bob
      && sharedA.accounts.alice.groups == [ "dialout" ]
      && sharedA.accounts.bob.groups == [ "dialout" ]
      && inspect shared.hostB == inspect baseline.hostB;

    removingOneConsumerKeepsSharedSupport =
      remainingA.accounts.alice == baselineA.accounts.alice
      && hasTools remainingA.accounts.bob
      && remainingA.accounts.bob.groups == [ "dialout" ]
      && additions remainingA == selectedRules
      && inspect remaining.hostB == inspect baseline.hostB;

    removingLastConsumerRemovesHostSupport =
      inspect afterLastConsumerRemoved.hostA == baselineA
      && inspect afterLastConsumerRemoved.hostB == inspect baseline.hostB;

    independentOfCommandLineAndGroupsRemainScoped =
      !selectedA.shell
      && !sharedA.shell
      && !mirroredB.shell
      && combinedA.shell
      && hasTools combinedA.accounts.alice
      && groups combined.hostA.config "alice" == [ "dialout" ]
      && groups combined.hostA.config "bob" == [ ]
      && groups combined.hostB.config "alice" == [ ];

    noGraphicalSessionIsIntroduced = lib.all (host: !(inspect host).graphical) [
      baseline.hostA
      selected.hostA
      shared.hostA
      mirrored.hostB
      combined.hostA
    ];
  };

  passed = lib.all (value: value) (builtins.attrValues result);
  selectedHost = combined.hostA.config;
  selectedHome = selectedHost.home-manager.users.alice;
  checks = import ../../aspects/embedded-workbench/checks.nix {
    inherit pkgs;
    profile = selectedHome.home.path;
    rules = selectedHost.environment.etc."udev/rules.d".source;
  };
in
{
  composition =
    assert lib.assertMsg passed
      "Embedded workbench composition failures: ${
        builtins.toJSON (lib.filterAttrs (_: value: !value) result)
      }";
    pkgs.runCommand "den-embedded-workbench-composition" { } ''
      mkdir -p "$out"
      cp ${pkgs.writeText "den-embedded-workbench-composition.json" (builtins.toJSON result)} "$out/results.json"
    '';
  home = selectedHome.home.activationPackage;
  inherit (checks) udev;
  inherit (checks) tools;
}
