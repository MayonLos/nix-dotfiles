{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  system = "x86_64-linux";
  palette = import ../../aspects/appearance/appearance/onedark-darker.nix;

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
          ../../aspects/appearance/appearance
          ../../aspects
        ];

        den = {
          systems = [ system ];
          schema.user.classes = [ "homeManager" ];

          hosts.${system} = lib.genAttrs [ "hostA" "hostB" ] (_: {
            appearance = palette;
            facts = hostFacts;
            avatar = {
              name = "alice";
              initial = "A";
            };
            users = {
              # Exercise two independent user preferences while both share the
              # same host-level compositor support.
              alice.avatar = {
                name = "alice";
                initial = "A";
              };
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
                  inherit pkgs;
                  specialArgs = (args.specialArgs or { }) // {
                    inherit inputs hostFacts;
                  };
                }
              );
          });

          default = {
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

          aspects = lib.genAttrs bindings (
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
              includes = map (name: den.aspects.${name}) (selected.${binding} or [ ]);
            }
          );
        };
      }
    )).nixosConfigurations;

  aliceOnly = evaluate { "alice@hostA" = [ "interactive-session" ]; };
  sharedHost = evaluate {
    "alice@hostA" = [ "interactive-session" ];
    "bob@hostA" = [ "interactive-session" ];
  };
  afterLastConsumerRemoved = evaluate { };
  avatarMango = evaluate {
    "alice@hostA" = [
      "avatar"
      "interactive-session"
    ];
  };
  avatarOnly = evaluate { "alice@hostA" = [ "avatar" ]; };
  avatarXorg = evaluate {
    "alice@hostA" = [
      "avatar"
      "xorg-session"
    ];
  };
  xorgOnly = evaluate { "alice@hostA" = [ "xorg-session" ]; };

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
  hasUserTarget = hm: name: builtins.hasAttr name hm.systemd.user.targets;
  hasXorgServices =
    hm:
    builtins.all (hasHomeUnit hm) [
      "picom"
      "dunst"
      "fcitx5-daemon"
    ];
  hasNoXorgServices =
    hm:
    builtins.all (name: !(hasHomeUnit hm name)) [
      "picom"
      "dunst"
      "fcitx5-daemon"
      "xorg-copyq"
      "xorg-polkit"
      "xorg-lock"
    ];
  hasXorgHostConfig =
    config:
    config.services.xserver.enable
    && config.services.xserver.displayManager.startx.enable
    && builtins.hasAttr "i3lock" config.security.pam.services
    && config.services.pipewire.enable
    && config.security.polkit.enable
    && config.xdg.portal.enable
    && config.xdg.portal.config ? dwm
    &&
      config.fonts.fontconfig.defaultFonts.sansSerif == [
        palette.fonts.sans
        palette.fonts.cjk
      ];

  selectedHost = host aliceOnly "hostA";
  unselectedHost = host aliceOnly "hostB";
  sharedHostConfig = host sharedHost "hostA";
  selectedHome = home aliceOnly "hostA" "alice";
  unselectedHome = home aliceOnly "hostA" "bob";
  sharedAliceHome = home sharedHost "hostA" "alice";
  sharedBobHome = home sharedHost "hostA" "bob";
  hostBHome = home aliceOnly "hostB" "alice";
  hostBBobHome = home aliceOnly "hostB" "bob";
  xorgHost = host xorgOnly "hostA";
  unselectedXorgHost = host xorgOnly "hostB";
  xorgAliceHome = home xorgOnly "hostA" "alice";
  unselectedXorgBobHome = home xorgOnly "hostA" "bob";
  unselectedXorgHostAliceHome = home xorgOnly "hostB" "alice";
  unselectedXorgHostBobHome = home xorgOnly "hostB" "bob";

  results = {
    fontRolesAndCursorReachTheirConsumers =
      selectedHost.fonts.fontconfig.defaultFonts.monospace == [ palette.fonts.mono ]
      && selectedHome.gtk.font.name == palette.fonts.sans
      && selectedHome.programs.noctalia.settings.shell.font_family == palette.fonts.sans
      &&
        selectedHome.i18n.inputMethod.fcitx5.settings.addons.classicui.globalSection.Font
        == "${palette.fonts.cjk} 13"
      && selectedHome.home.pointerCursor.name == palette.cursor.name
      && selectedHome.home.pointerCursor.size == palette.cursor.size
      && xorgAliceHome.services.dunst.iconTheme.name == palette.iconTheme
      && selectedHome.gtk.iconTheme.name == palette.iconTheme
      && xorgAliceHome.home.pointerCursor.name == palette.cursor.name;

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

      &&
        selectedHost.fonts.fontconfig.defaultFonts.sansSerif == [
          palette.fonts.sans
          palette.fonts.cjk
        ]
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
      && !sharedAliceHome.programs.noctalia.settings.wallpaper.transition_on_startup
      && sharedAliceHome.programs.noctalia.settings.wallpaper.automation.enabled
      && sharedBobHome.programs.noctalia.settings.wallpaper.automation.enabled
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

    xorgSessionSelectsXorgAndSharedSupportOnly =
      hasXorgHostConfig xorgHost
      && !(xorgHost.programs.mango.enable or false)
      && !(xorgHost.xdg.portal.wlr.enable or false)
      && !(xorgHost.xdg.portal.config ? mango)
      && xorgAliceHome.i18n.inputMethod.enable
      && xorgAliceHome.gtk.enable
      && xorgAliceHome.home.sessionVariables.QT_QPA_PLATFORMTHEME == "qt6ct"
      && xorgAliceHome.systemd.user.sessionVariables.XMODIFIERS == "@im=fcitx"
      && !(xorgAliceHome.home.sessionVariables ? NIXOS_OZONE_WL)
      && !(xorgAliceHome.systemd.user.sessionVariables ? NIXOS_OZONE_WL)
      && xorgAliceHome.xresources.properties."Xft.dpi" == hostFacts.display.x11Dpi
      && builtins.hasAttr "seedQt6ctConfig" xorgAliceHome.home.activation
      && builtins.hasAttr "seedQt6ctPalette" xorgAliceHome.home.activation
      && hasXorgServices xorgAliceHome
      && hasUserTarget xorgAliceHome "xorg-session"
      && builtins.elem "pipewire.socket" xorgAliceHome.systemd.user.targets.xorg-session.Unit.Wants
      && hasHomeUnit xorgAliceHome "xrdb-merge"
      && !(xorgAliceHome.programs.mango.enable or false)
      && !(xorgAliceHome.wayland.windowManager.mango.enable or false)
      && !(xorgAliceHome.programs.noctalia.enable or false)
      && !(xorgAliceHome.systemd.user.targets ? mango-session)
      && !(hasHomeUnit xorgAliceHome "noctalia")
      && !(hasHomeUnit xorgAliceHome "clipboard-bridge");

    removingAvatarRemovesWidget =
      !(
        selectedHome.programs.noctalia.settings.lockscreen_widgets.widget or { } ? lockscreen-widget-avatar
      )
      && (
        (home avatarMango "hostA" "alice").programs.noctalia.settings.lockscreen_widgets.widget
          ? lockscreen-widget-avatar
      );

    avatarDoesNotSelectMango =
      (home avatarOnly "hostA" "alice").xdg.dataFile ? "nix-dotfiles/alice-avatar.png"
      && !((home avatarOnly "hostA" "alice").programs.noctalia.enable or false)
      && !((home avatarXorg "hostA" "alice").programs.noctalia.enable or false)
      && (home avatarXorg "hostA" "alice").xdg.dataFile ? "nix-dotfiles/alice-avatar.png";

    xorgSelectionDoesNotCrossAccountsOrHosts =
      hasNoXorgServices unselectedXorgBobHome
      && !(hasUserTarget unselectedXorgBobHome "xorg-session")
      && !unselectedXorgBobHome.i18n.inputMethod.enable
      && !(hasXorgHostConfig unselectedXorgHost)
      && !(unselectedXorgHost.programs.mango.enable or false)
      && hasNoXorgServices unselectedXorgHostAliceHome
      && !(hasUserTarget unselectedXorgHostAliceHome "xorg-session")
      && hasNoXorgServices unselectedXorgHostBobHome
      && !(hasUserTarget unselectedXorgHostBobHome "xorg-session");
  };

  # Execute the real Xorg-only palette seed against a temporary XDG home,
  # never the fixture account's /home path.
  qtSeed = pkgs.writeText "xorg-qt-palette-seed.sh" (
    lib.replaceStrings [ xorgAliceHome.xdg.configHome ] [ "$XDG_CONFIG_HOME" ]
      xorgAliceHome.home.activation.seedQt6ctPalette.data
  );
  qtFontMigration = pkgs.writeText "xorg-qt-font-migration.sh" (
    lib.replaceStrings [ xorgAliceHome.xdg.configHome ] [ "$XDG_CONFIG_HOME" ]
      xorgAliceHome.home.activation.migrateQt6ctFonts.data
  );
  passed = lib.all (value: value) (builtins.attrValues results);
  report = pkgs.writeText "den-interactive-session-composition.json" (builtins.toJSON results);
in
assert lib.assertMsg passed
  "Interactive-session composition failures: ${
    builtins.toJSON (lib.filterAttrs (_: value: !value) results)
  }";
pkgs.runCommand "den-interactive-session-composition" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache" XDG_STATE_HOME="$TMPDIR/state" XDG_DATA_HOME="$TMPDIR/data"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"
  mkdir -p "$out"
  cp ${report} "$out/results.json"
  run() { "$@"; }
  source ${qtSeed}
  python3 - "$XDG_CONFIG_HOME/qt6ct/colors/noctalia.conf" <<'PY_QT'
  import configparser, re, sys
  from pathlib import Path
  path = Path(sys.argv[1])
  palette = configparser.ConfigParser()
  palette.read(path)
  for group in ("active_colors", "disabled_colors", "inactive_colors"):
      colors = [value.strip() for value in palette["ColorScheme"][group].split(",")]
      assert len(colors) == 22 and all(re.fullmatch(r"#[0-9a-fA-F]{6}", value) for value in colors)
  assert "${palette.bg}" in palette["ColorScheme"]["active_colors"]
  path.write_text("existing GUI-owned palette\n")
  PY_QT
  source ${qtSeed}
  grep -Fx 'existing GUI-owned palette' "$XDG_CONFIG_HOME/qt6ct/colors/noctalia.conf" > "$out/qt-seed-preserves-existing.txt"
  mkdir -p "$XDG_CONFIG_HOME/qt6ct"
  cat > "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" <<'QT_OLD'
  [Appearance]
  style=CustomStyle
  [Fonts]
  general=Noto Sans CJK SC,11,-1,5,400,0,0,0,0,0
  fixed=JetBrainsMono Nerd Font,11,-1,5,400,0,0,0,0,0
  [Unknown]
  value=keep me
  QT_OLD
  source ${qtFontMigration}
  cp "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "$out/qt-font-migrated.conf"
  grep -Fx 'general=${palette.fonts.sans},11,-1,5,400,0,0,0,0,0' "$out/qt-font-migrated.conf"
  grep -Fx 'fixed=${palette.fonts.mono},11,-1,5,400,0,0,0,0,0' "$out/qt-font-migrated.conf"
  grep -Fx 'style=CustomStyle' "$out/qt-font-migrated.conf"
  grep -Fx 'value=keep me' "$out/qt-font-migrated.conf"
  source ${qtFontMigration}
  cmp "$out/qt-font-migrated.conf" "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf"
  sed -i 's/^general=.*/general=User Choice,12,-1,5,400,0,0,0,0,0/' "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf"
  cp "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "$out/qt-font-custom.conf"
  source ${qtFontMigration}
  cmp "$out/qt-font-custom.conf" "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf"
  # Validate the reduced-motion branch with the actual pinned parsers as well
  # as checking its composition. The real host check covers the rich default.
  ${lib.getExe sharedAliceHome.programs.noctalia.package} config validate ${
    sharedAliceHome.xdg.configFile."noctalia/config.toml".source
  } > "$out/noctalia-reduced-motion.log" 2>&1 || { cat "$out/noctalia-reduced-motion.log"; exit 1; }
  if grep -iE '\[WARN\]|warning:|\[ERROR\]|^WARN[[:space:]]|[1-9][0-9]* warning\(s\)' "$out/noctalia-reduced-motion.log"; then exit 1; fi
  ${lib.getExe sharedAliceHome.wayland.windowManager.mango.package} -c ${
    sharedAliceHome.xdg.configFile."mango/config.conf".source
  } -p > "$out/mango-reduced-motion.log" 2>&1 || { cat "$out/mango-reduced-motion.log"; exit 1; }
  if grep -iE 'conflict|unknown|invalid|error' "$out/mango-reduced-motion.log"; then exit 1; fi
''
