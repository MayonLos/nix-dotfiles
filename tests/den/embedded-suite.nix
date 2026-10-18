{
  evaluate,
  lib,
  pkgs,
  stlinkRules,
}:
let
  baseline = evaluate { };
  selected = evaluate { embeddedChoices = [ "alice@probe-a" ]; };
  shared = evaluate {
    embeddedChoices = [
      "alice@probe-a"
      "bob@probe-a"
    ];
  };
  mirrored = evaluate { embeddedChoices = [ "bob@probe-b" ]; };
  remaining = evaluate { embeddedChoices = [ "bob@probe-a" ]; };
  combined = evaluate {
    choices = [ "alice@probe-a" ];
    embeddedChoices = [ "alice@probe-a" ];
  };
  toolNames = [
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
  inspect =
    host:
    let
      c = host.config;
    in
    {
      rules = map toString c.services.udev.packages;
      accounts = lib.genAttrs [ "alice" "bob" ] (name: {
        groups = c.users.users.${name}.extraGroups;
        tools = map (p: p.pname or (lib.getName p)) c.home-manager.users.${name}.home.packages;
      });
      graphical = c.services.xserver.enable || c.services.displayManager.enable || c.programs.sway.enable;
      shell = c.programs.zsh.enable;
    };
  base = inspect baseline.probe-a;
  a = inspect selected.probe-a;
  both = inspect shared.probe-a;
  mirror = inspect mirrored.probe-b;
  hasTools = account: lib.all (name: lib.elem name account.tools) toolNames;
  noTools = account: !lib.any (name: lib.elem name account.tools) toolNames;
  additions = host: builtins.filter (p: !(lib.elem p base.rules)) host.rules;
  selectedRules = additions a;
  rulePackages = map toString [
    pkgs.openocd
    stlinkRules
  ];
  results = {
    unselected =
      noTools base.accounts.alice
      && noTools base.accounts.bob
      && base.accounts.alice.groups == [ ]
      && base.accounts.bob.groups == [ ]
      && !lib.any (p: lib.elem p base.rules) rulePackages;
    completeFeature =
      hasTools a.accounts.alice
      && a.accounts.alice.groups == [ "dialout" ]
      && lib.all (p: lib.elem p selectedRules) rulePackages
      && builtins.length selectedRules == 3;
    otherAccountUntouched = a.accounts.bob == base.accounts.bob;
    otherHostUntouched = inspect selected.probe-b == inspect baseline.probe-b;
    mirroredSelection =
      hasTools mirror.accounts.bob
      && mirror.accounts.bob.groups == [ "dialout" ]
      && mirror.accounts.alice == base.accounts.alice
      && additions mirror == selectedRules
      && inspect mirrored.probe-a == base;
    sharedSupport =
      additions both == selectedRules
      && builtins.length (lib.unique selectedRules) == builtins.length selectedRules
      && hasTools both.accounts.alice
      && hasTools both.accounts.bob
      && both.accounts.alice.groups == [ "dialout" ]
      && both.accounts.bob.groups == [ "dialout" ]
      && inspect shared.probe-b == inspect baseline.probe-b;
    removingOneUserKeepsSupport =
      (inspect remaining.probe-a).accounts.alice == base.accounts.alice
      && hasTools (inspect remaining.probe-a).accounts.bob
      && (inspect remaining.probe-a).accounts.bob.groups == [ "dialout" ]
      && additions (inspect remaining.probe-a) == selectedRules
      && inspect remaining.probe-b == inspect baseline.probe-b;
    independentFeatures =
      !a.shell
      && !both.shell
      && !mirror.shell
      && (inspect combined.probe-a).shell
      && hasTools (inspect combined.probe-a).accounts.alice
      &&
        lib.sort builtins.lessThan (inspect combined.probe-a).accounts.alice.groups == [
          "den-shell"
          "dialout"
        ];
    noGraphicalSession = lib.all (host: !host.graphical) [
      base
      a
      both
      mirror
      (inspect combined.probe-a)
    ];
  };
in
{
  inherit results;
  observations = {
    baseline = base;
    selected = a;
    shared = both;
    mirrored = mirror;
  };
  passed =
    lib.assertMsg (lib.all (x: x) (lib.attrValues results))
      "Den embedded failures: ${builtins.toJSON (lib.filterAttrs (_: value: !value) results)}";
}
