{ inputs, pkgs }:
let
  lib = inputs.nixpkgs.lib;
  system = "x86_64-linux";

  evaluate =
    selected:
    (inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { den, ... }:
      {
        imports = [
          inputs.den.flakeModule
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
          };
          homeManager = {
            home.stateVersion = "26.05";
          };
        };

        den.aspects = lib.genAttrs [ "alice@hostA" "bob@hostA" "alice@hostB" "bob@hostB" ] (binding: {
          user.isNormalUser = true;
          homeManager.home = {
            username = builtins.head (lib.splitString "@" binding);
            homeDirectory = "/home/${builtins.head (lib.splitString "@" binding)}";
          };
          includes = lib.optionals (builtins.elem binding selected) [ den.aspects.command-line ];
        });
      }
    )).nixosConfigurations;

  baseline = evaluate [ ];
  aliceOnly = evaluate [ "alice@hostA" ];
  sharedHost = evaluate [
    "alice@hostA"
    "bob@hostA"
  ];
  afterLastConsumerRemoved = baseline;

  hm =
    configs: host: user:
    configs.${host}.config.home-manager.users.${user};
  host = configs: name: configs.${name}.config;

  hasPackage =
    home: pname:
    builtins.elem pkgs.${pname}.outPath (map (package: package.outPath) home.home.packages);

  cliToolPackages = [
    "bat"
    "eza"
    "ripgrep"
    "duf"
    "nix-output-monitor"
    "fd"
    "jq"
    "hexyl"
    "dust"
    "tealdeer"
    "sops"
    "p7zip"
    "libqalculate"
  ];
  hasCliTools = home: builtins.all (pname: hasPackage home pname) cliToolPackages;
  noCliTools = home: builtins.all (pname: !(hasPackage home pname)) cliToolPackages;

  cliEnabled =
    home:
    home.programs.zsh.enable
    && home.programs.git.enable
    && home.programs.direnv.enable
    && home.programs.nix-index.enable
    && home.programs.tmux.enable
    && home.programs.yazi.enable
    && home.programs.fastfetch.enable
    && home.programs.btop.enable;

  selectedHome = hm aliceOnly "hostA" "alice";
  sharedHostConfig = host sharedHost "hostA";
  noCliHostConfig = host baseline "hostA";

  results = {
    selectedBindingGetsCli =
      cliEnabled selectedHome
      && (host aliceOnly "hostA").users.users.alice.shell.pname == "zsh"
      && hasCliTools selectedHome
      && hasPackage selectedHome "eza"
      && hasPackage selectedHome "ripgrep"
      && hasPackage selectedHome "jq";

    otherAccountAndHostUntouched =
      !(cliEnabled (hm aliceOnly "hostA" "bob"))
      && !(cliEnabled (hm aliceOnly "hostB" "alice"))
      && !(cliEnabled (hm aliceOnly "hostB" "bob"))
      && noCliTools (hm aliceOnly "hostA" "bob")
      && noCliTools (hm aliceOnly "hostB" "alice")
      && noCliTools (hm aliceOnly "hostB" "bob")
      && (host aliceOnly "hostA").users.users.bob.shell.pname != "zsh"
      && !(host aliceOnly "hostB").programs.zsh.enable;

    hostSupportOnlyFollowsSelectedBindings =
      (host aliceOnly "hostA").programs.zsh.enable
      && !(host aliceOnly "hostB").programs.zsh.enable
      && !noCliHostConfig.programs.zsh.enable
      && !(host afterLastConsumerRemoved "hostA").programs.zsh.enable;

    sharedHostSupportCoexists =
      sharedHostConfig.programs.zsh.enable
      && cliEnabled (hm sharedHost "hostA" "alice")
      && cliEnabled (hm sharedHost "hostA" "bob")
      && hasCliTools (hm sharedHost "hostA" "alice")
      && hasCliTools (hm sharedHost "hostA" "bob")
      && !(host sharedHost "hostB").programs.zsh.enable
      && !(cliEnabled (hm sharedHost "hostB" "alice"));

    remoteCliHasNoDesktopOrLocalOnlyFeatures =
      !(selectedHome.programs.kitty.enable or false)
      && !(selectedHome.programs ? mango)
      && !(selectedHome.programs ? noctalia)
      && !(selectedHome.programs.java.enable or false)
      && !(selectedHome.i18n.inputMethod.enable or false)
      && !(hasPackage selectedHome "kitty")
      && !(hasPackage selectedHome "noctalia-shell")
      && !(hasPackage selectedHome "jdk")
      && !(host aliceOnly "hostA").services.greetd.enable
      && !(host aliceOnly "hostA").services.xserver.enable;

    remoteCliHasNoSecretOrDeviceAuthorization =
      !((host aliceOnly "hostA") ? sops)
      && !(lib.hasInfix "/run/secrets" selectedHome.programs.zsh.initContent)
      && (host aliceOnly "hostA").users.users.alice.extraGroups == [ ];

    btopUsesBuiltInDefault = selectedHome.programs.btop.settings.color_theme == "Default";

    removingFinalConsumerRemovesHostDeclaration =
      !(host afterLastConsumerRemoved "hostA").programs.zsh.enable;
  };

  passed = lib.all (value: value) (builtins.attrValues results);
  report = pkgs.writeText "den-command-line-composition.json" (builtins.toJSON results);
in
assert lib.assertMsg passed
  "Command-line composition failures: ${
    builtins.toJSON (lib.filterAttrs (_: value: !value) results)
  }";
pkgs.runCommand "den-command-line-composition" { } ''
  mkdir -p "$out"
  cp ${report} "$out/results.json"
''
