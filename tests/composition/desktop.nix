{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  system = "x86_64-linux";
  palette = import ../../aspects/appearance/onedark-darker.nix;

  # Public fixture facts only. These values make the actual Mango/Noctalia
  # modules evaluable; the fixture does not represent another deployable host.
  hostFacts = {
    inherit system;
    gpu = {
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
    keyboardDevices = [ "/dev/input/by-id/fixture-keyboard" ];
    display = {
      name = "eDP-1";
      scale = 1.5;
      width = 2560;
      height = 1600;
      refresh = 165.002;
      x11Dpi = 144;
    };
  };

  bindings = [
    "alice@hostA"
    "bob@hostA"
    "alice@hostB"
    "bob@hostB"
  ];

  evaluate =
    selected:
    (inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      # Den's root API is captured at mkFlake scope; aspect module args do not
      # contain this registry.
      { den, ... }:
      {
        imports = [
          inputs.den.flakeModule
          ../../aspects/appearance
          ../../aspects/interactive-session
        ];

        den.systems = [ system ];
        den.schema.user.classes = [ "homeManager" ];

        den.hosts.${system} = lib.genAttrs [ "hostA" "hostB" ] (_: {
          appearance = palette;
          users = {
            # Exercise two independent user preferences while both share the
            # same host-level compositor support.
            alice.appearance = palette // {
              reducedMotion = true;
            };
            bob.appearance = palette // {
              reducedMotion = false;
            };
          };
          instantiate =
            args:
            inputs.nixpkgs.lib.nixosSystem (
              args
              // {
                specialArgs = (args.specialArgs or { }) // {
                  inherit inputs hostFacts;
                };
              }
            );
        });

        den.default = {
          nixos = {
            system.stateVersion = "26.05";
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            home-manager.useGlobalPkgs = true;
            home-manager.extraSpecialArgs = {
              inherit inputs hostFacts;
            };
          };
          homeManager.home.stateVersion = "26.05";
        };

        den.aspects = lib.genAttrs bindings (
          binding:
          let
            user = builtins.head (lib.splitString "@" binding);
          in
          {
            user.isNormalUser = true;
            homeManager = {
              home.username = user;
              home.homeDirectory = "/home/${user}";
            };
            includes = lib.optionals (lib.elem binding selected) [ den.aspects.interactive-session ];
          }
        );
      }
    )).nixosConfigurations;

  aliceOnly = evaluate [ "alice@hostA" ];
  sharedHost = evaluate [
    "alice@hostA"
    "bob@hostA"
  ];
  afterLastConsumerRemoved = evaluate [ ];

  host = configs: name: configs.${name}.config;
  home =
    configs: hostName: user:
    (host configs hostName).home-manager.users.${user};

  hasHomeUnit = hm: name: builtins.hasAttr name hm.systemd.user.services;
  desktopUnits = [
    "noctalia"
    "fcitx5-daemon"
    "clipboard-bridge"
  ];
  hasAllDesktopUnits = hm: builtins.all (hasHomeUnit hm) desktopUnits;
  hasNoDesktopUnits = hm: builtins.all (name: !(hasHomeUnit hm name)) desktopUnits;
  hasInputGroup = config: user: builtins.elem "input" config.users.users.${user}.extraGroups;

  selectedHost = host aliceOnly "hostA";
  unselectedHost = host aliceOnly "hostB";
  sharedHostConfig = host sharedHost "hostA";
  selectedHome = home aliceOnly "hostA" "alice";
  unselectedHome = home aliceOnly "hostA" "bob";
  sharedAliceHome = home sharedHost "hostA" "alice";
  sharedBobHome = home sharedHost "hostA" "bob";
  hostBHome = home aliceOnly "hostB" "alice";
  hostBBobHome = home aliceOnly "hostB" "bob";

  results = {
    audioActivationIsBindingScoped =
      selectedHost.systemd.user.sockets.pipewire.wantedBy == [ ]
      && selectedHost.systemd.user.sockets.pipewire-pulse.wantedBy == [ ]
      && builtins.elem "pipewire.socket" selectedHome.systemd.user.targets.mango-session.Unit.Wants
      && !(unselectedHome.systemd.user.targets ? mango-session);

    browserIntegrationRequiresBrowserSelection =
      !(selectedHome.programs.noctalia.settings.theme.templates.user ? noctalia-firefox);

    selectedUserGetsDesktopAndInputAuthorization =
      selectedHost.programs.mango.enable
      && selectedHost.services.pipewire.enable
      && selectedHost.xdg.portal.enable

      && selectedHost.fonts.fontconfig.defaultFonts.sansSerif == [ palette.fonts.sans ]
      && selectedHome.programs.noctalia.enable
      && selectedHome.programs.noctalia.customPalettes.One-Dark-Darker.dark.mSurface == palette.bg
      && selectedHome.i18n.inputMethod.enable
      && hasAllDesktopUnits selectedHome
      && hasInputGroup selectedHost "alice";

    selectionDoesNotCrossUsersOrHosts =
      selectedHost.programs.mango.enable
      && !hasInputGroup selectedHost "bob"
      && hasNoDesktopUnits unselectedHome
      && !unselectedHome.i18n.inputMethod.enable
      && !hasInputGroup unselectedHost "alice"
      && !(unselectedHost.programs.mango.enable or false)
      && !unselectedHost.services.pipewire.enable
      && !unselectedHost.xdg.portal.enable
      && hasNoDesktopUnits hostBHome
      && hasNoDesktopUnits hostBBobHome;

    sharedHostSupportIsDeliveredOnceForBothConsumers =
      sharedHostConfig.programs.mango.enable
      && sharedHostConfig.services.pipewire.enable
      && sharedHostConfig.xdg.portal.enable

      && builtins.all (user: hasInputGroup sharedHostConfig user) [
        "alice"
        "bob"
      ]
      && builtins.all (user: hasAllDesktopUnits (home sharedHost "hostA" user)) [
        "alice"
        "bob"
      ]
      && sharedAliceHome.wayland.windowManager.mango.settings.animations == 0
      && sharedBobHome.wayland.windowManager.mango.settings.animations == 1
      && !sharedAliceHome.programs.noctalia.settings.shell.animation.enabled
      && sharedBobHome.programs.noctalia.settings.shell.animation.enabled
      && sharedAliceHome.programs.noctalia.settings.wallpaper.transition == [ ]
      && sharedBobHome.programs.noctalia.settings.wallpaper.transition == [ "fade" ]
      && sharedAliceHome.programs.noctalia.settings.lockscreen.transition == [ ]
      && sharedBobHome.programs.noctalia.settings.lockscreen.transition == [ "fade" ]
      && !((host sharedHost "hostB").programs.mango.enable or false);

    desktopDoesNotSelectLoginScreen =
      !(selectedHost.services.displayManager.noctalia-greeter.enable or false)
      && !((host sharedHost "hostA").services.displayManager.noctalia-greeter.enable or false)
      && !((host afterLastConsumerRemoved "hostA").services.displayManager.noctalia-greeter.enable
        or false
      );

    unselectedHostHasNoSecretProxyOrDeviceAuthorization =
      !(unselectedHost ? sops)
      && !(unselectedHost.systemd.services.nix-daemon.environment ? https_proxy)
      && !(unselectedHost.systemd.services.nix-daemon.environment ? http_proxy)
      && unselectedHost.users.users.alice.extraGroups == [ ]
      && unselectedHost.users.users.bob.extraGroups == [ ];

    removingLastConsumerRemovesHostSupport =
      !((host afterLastConsumerRemoved "hostA").programs.mango.enable or false)
      && !(host afterLastConsumerRemoved "hostA").services.pipewire.enable
      && !(host afterLastConsumerRemoved "hostA").xdg.portal.enable
      && hasNoDesktopUnits (home afterLastConsumerRemoved "hostA" "alice")
      && hasNoDesktopUnits (home afterLastConsumerRemoved "hostA" "bob");
  };

  passed = lib.all (value: value) (builtins.attrValues results);
  report = pkgs.writeText "den-interactive-session-composition.json" (builtins.toJSON results);
in
assert lib.assertMsg passed
  "Interactive-session composition failures: ${
    builtins.toJSON (lib.filterAttrs (_: value: !value) results)
  }";
pkgs.runCommand "den-interactive-session-composition" { } ''
  export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache" XDG_STATE_HOME="$TMPDIR/state" XDG_DATA_HOME="$TMPDIR/data"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"
  mkdir -p "$out"
  cp ${report} "$out/results.json"
  # Validate the reduced-motion branch with the actual pinned parsers as well
  # as checking its composition. The real host check covers the rich default.
  ${lib.getExe sharedAliceHome.programs.noctalia.package} config validate ${
    sharedAliceHome.xdg.configFile."noctalia/config.toml".source
  } > "$out/noctalia-reduced-motion.log" 2>&1 || { cat "$out/noctalia-reduced-motion.log"; exit 1; }
  if grep -iE '\[WARN\]|warning:|\[ERROR\]' "$out/noctalia-reduced-motion.log"; then exit 1; fi
  ${lib.getExe sharedAliceHome.wayland.windowManager.mango.package} -c ${
    sharedAliceHome.xdg.configFile."mango/config.conf".source
  } -p > "$out/mango-reduced-motion.log" 2>&1 || { cat "$out/mango-reduced-motion.log"; exit 1; }
  if grep -iE 'conflict|unknown|invalid|error' "$out/mango-reduced-motion.log"; then exit 1; fi
''
