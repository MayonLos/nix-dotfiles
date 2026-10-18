{ evaluate, lib }:
let
  baseline = evaluate { };
  selected = evaluate { choices = [ "alice@probe-a" ]; };
  mirrored = evaluate { choices = [ "bob@probe-b" ]; };
  shared = evaluate {
    choices = [
      "alice@probe-a"
      "bob@probe-a"
    ];
  };
  conflicting = evaluate {
    choices = [ "alice@probe-a" ];
    conflictingSupport = true;
  };
  inspect =
    host:
    let
      c = host.config;
    in
    {
      shellSupport = c.programs.zsh.enable;
      supportFile = c.environment.etc ? den-shell-support;
      supportGroup = c.users.groups ? den-shell;
      supportMode =
        if c.environment.etc ? den-shell-support then c.environment.etc.den-shell-support.mode else null;
      desktop = c.services.xserver.enable || c.services.displayManager.enable || c.programs.sway.enable;
      accounts = lib.genAttrs [ "alice" "bob" ] (
        name:
        let
          u = c.users.users.${name};
          hm = c.home-manager.users.${name};
        in
        {
          shell = u.shell.pname;
          normalUser = u.isNormalUser;
          groups = u.extraGroups;
          hmShell = hm.programs.zsh.enable;
          marker = hm.home.sessionVariables.DEN_COMMAND_LINE or null;
        }
      );
    };
  plain = {
    shell = "bash-interactive";
    normalUser = true;
    groups = [ ];
    hmShell = false;
    marker = null;
  };
  enabled = {
    shell = "zsh";
    normalUser = true;
    groups = [ "den-shell" ];
    hmShell = true;
    marker = "selected";
  };
  a = inspect selected.probe-a;
  b = inspect selected.probe-b;
  both = inspect shared.probe-a;
  results = {
    unselectedHost =
      inspect baseline.probe-a == {
        shellSupport = false;
        supportFile = false;
        supportGroup = false;
        supportMode = null;
        desktop = false;
        accounts = {
          alice = plain;
          bob = plain;
        };
      };
    completeFeature =
      a.shellSupport
      && a.supportFile
      && a.supportGroup
      && a.supportMode == "0444"
      && a.accounts.alice == enabled;
    otherAccountUntouched = a.accounts.bob == plain;
    otherHostUntouched = b == inspect baseline.probe-b;
    mirroredSelection =
      (inspect mirrored.probe-b).accounts.bob == enabled
      && (inspect mirrored.probe-b).accounts.alice == plain
      && (inspect mirrored.probe-b).shellSupport
      && (inspect mirrored.probe-b).supportFile
      && (inspect mirrored.probe-b).supportGroup
      && (inspect mirrored.probe-b).supportMode == "0444"
      && inspect mirrored.probe-a == inspect baseline.probe-a;
    portableIdentity =
      lib.all
        (
          hosts:
          lib.all
            (
              host:
              lib.all
                (name: hosts.${host}.config.home-manager.users.${name}.home.sessionVariables.DEN_IDENTITY == name)
                [
                  "alice"
                  "bob"
                ]
            )
            [
              "probe-a"
              "probe-b"
            ]
        )
        [
          baseline
          selected
          shared
          mirrored
        ];
    sharedSupport =
      both.shellSupport
      && both.supportFile
      && both.supportGroup
      && both.accounts.alice == enabled
      && both.accounts.bob == enabled
      && shared.probe-a.config.environment.etc.den-shell-support.text == "shared host support\n"
      && inspect shared.probe-b == inspect baseline.probe-b;
    headless = !a.desktop && !b.desktop && !both.desktop && !(inspect mirrored.probe-b).desktop;
    conflictingWriterRejected =
      !(builtins.tryEval conflicting.probe-a.config.environment.etc.den-shell-support.mode).success;
  };
in
{
  inherit results;
  observations = {
    baseline = inspect baseline.probe-a;
    selected = a;
    otherHost = b;
    shared = both;
    sharedText = shared.probe-a.config.environment.etc.den-shell-support.text;
  };
  passed =
    lib.assertMsg (lib.all (x: x) (lib.attrValues results))
      "Den composition failures: ${builtins.toJSON (lib.filterAttrs (_: value: !value) results)}";
}
