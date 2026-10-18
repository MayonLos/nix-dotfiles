{
  choices,
  conflictingSupport,
  embeddedChoices,
  userSettings,
  featureChoices,
}:
{
  den,
  lib,
  inputs,
  ...
}:
{
  imports = [
    "${inputs.embedded-workbench}/default.nix"
    ./contracts-fixture.nix
  ];
  den.hosts.x86_64-linux = lib.genAttrs [ "probe-a" "probe-b" ] (host: {
    users = lib.genAttrs [ "alice" "bob" ] (name: userSettings."${name}@${host}" or { });
  });

  den.schema.user.classes = [ "homeManager" ];
  den.default = {
    nixos = {
      system.stateVersion = "26.05";
      # Evaluation fixtures only: these machines are never exported for deployment.
      boot.loader.grub.enable = false;
      fileSystems."/" = {
        device = "none";
        fsType = "tmpfs";
      };
      home-manager.useGlobalPkgs = true;
      nixpkgs.config.allowUnfree = true;
    };
    homeManager.home.stateVersion = "26.05";
  };

  den.aspects = {
    # Portable identity composes with each host-qualified binding.
    alice.homeManager.home.sessionVariables.DEN_IDENTITY = "alice";
    bob.homeManager.home.sessionVariables.DEN_IDENTITY = "bob";

    command-line = { host, ... }: {
      homeManager = {
        programs.zsh.enable = true;
        home.sessionVariables.DEN_COMMAND_LINE = "selected";
      };
      user = { pkgs, ... }: {
        shell = pkgs.zsh;
        extraGroups = [ "den-shell" ];
      };
      # Explicit host delivery; do not rely on bare user-scoped nixos.
      provides.${host.name}.includes = [ den.aspects.shell-host-support ];
    };
    shell-host-support = {
      nixos = {
        programs.zsh.enable = true;
        users.groups.den-shell = { };
        environment.etc."den-shell-support" = {
          text = "shared host support\n";
          mode = "0444";
        };
      };
    };
    # Conflicting modes for the same file must fail when evaluated.
    conflicting-support = { host, ... }: {
      provides.${host.name}.nixos.environment.etc."den-shell-support".mode = "0644";
    };
  }
  // lib.genAttrs [ "alice@probe-a" "bob@probe-a" "alice@probe-b" "bob@probe-b" ] (binding: {
    user.isNormalUser = true;
    includes =
      lib.optionals (lib.elem binding choices) (
        [ den.aspects.command-line ] ++ lib.optional conflictingSupport den.aspects.conflicting-support
      )
      ++ lib.optional (lib.elem binding embeddedChoices) den.aspects.embedded-workbench
      ++ map (name: den.aspects.${name}) (featureChoices.${binding} or [ ]);
  });
}
