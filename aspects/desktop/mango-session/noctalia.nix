{
  palette,
  avatar ? null,
  noctaliaIntegrations ? [ ],
  integrationTemplates ? { },
}:
{
  config,
  lib,
  pkgs,
  inputs,
  hostFacts,
  ...
}:

let
  reducedMotion = palette.reducedMotion or false;
  # Native Soft mode is 0.80 in the pinned source. Share its opacity with
  # transient surfaces; Mango supplies blur for these namespaces.
  panelSurface = {
    mode = "soft";
    opacity = 0.80;
    shadow = false;
  };
  logicalWidth = hostFacts.display.width / hostFacts.display.scale;
  logicalHeight = hostFacts.display.height / hostFacts.display.scale;
  wallpapers = import ../../appearance/appearance/resources/wallpaper/package.nix {
    inherit pkgs palette;
  };
  wallpaperRoot = "${config.home.homeDirectory}/Pictures/Wallpapers";
  desktop = {
    primaryOutput = hostFacts.display.name;
  };
  reconcilePython = pkgs.python3.withPackages (p: [ p.tomlkit ]);
  managedSettings = pkgs.writeText "noctalia-managed-settings.json" (
    builtins.toJSON config.programs.noctalia.settings
  );
  reconcileOverrides = pkgs.writeShellScript "reconcile-noctalia-overrides" ''
    exec ${reconcilePython}/bin/python3 ${./resources/reconcile-overrides.py} \
      --state ${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/settings.toml"} \
      --managed ${managedSettings} \
      --backup-dir ${lib.escapeShellArg "${config.xdg.stateHome}/nix-dotfiles/ownership-backups"} \
      --require-no-noctalia
  '';

  defaultWallpaperPath = wallpapers.default;

  lowBatterySuspend = pkgs.writeShellScript "noctalia-low-battery-suspend" ''
    set -euo pipefail
    threshold=5
    state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/noctalia"
    state_file="$state_dir/hook-battery-percent"
    percent="''${NOCTALIA_BATTERY_PERCENT:-}"
    battery_state="''${NOCTALIA_BATTERY_STATE:-unknown}"

    [[ "$percent" =~ ^[0-9]+$ ]] || exit 0

    mkdir -p "$state_dir"
    previous=""
    [[ -r "$state_file" ]] && previous="$(<"$state_file")"
    printf '%s\n' "$percent" > "$state_file"

    [[ "$battery_state" == "discharging" ]] || exit 0
    [[ "$previous" =~ ^[0-9]+$ ]] || exit 0

    if (( previous >= threshold && percent < threshold )); then
      ${pkgs.systemd}/bin/systemctl suspend
    fi
  '';

  # Use only the static variables explicitly exported to the user manager.
  # Never import the full Home Manager environment or interpolate secrets.
  safeSessionVariables =
    (import ./session-environment.nix { inherit lib; })
      config.systemd.user.sessionVariables;

  noctaliaPackage = pkgs.local.noctalia.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./noctalia/astra-selection.patch
      ./noctalia/tech-lockscreen.patch
      ./noctalia/nvidia-sampler.patch
      ./noctalia/active-app-name.patch
      ./noctalia/launchpad-native.patch
      ./noctalia/desktop-menus.patch
      ./noctalia/r43-control-center.patch
      ./noctalia/r43-notifications.patch
      ./noctalia/r43-osd.patch
      ./noctalia/r43-calendar.patch
      ./noctalia/r43-settings.patch
      ./noctalia/r43-wallpaper.patch
      ./noctalia/r44-status-icons.patch
    ];
    # Fail on source drift, including the independently maintained panel patches.
    postPatch = (old.postPatch or "") + ''
      ${pkgs.python3}/bin/python3 ${./noctalia/r43-check-panels.py}
      ${pkgs.python3}/bin/python3 ${./noctalia/r44-check-status.py}
      grep -Fq 'R39: reuse native desktop scanning' src/app/application_ipc.cpp
      grep -Fq 'R39: Dock owns the Launchpad entry' src/shell/dock/dock.cpp
      grep -Fq 'R39: explicit capture consumes' src/shell/plugin_layer/plugin_layer.cpp
      grep -Fq 'R39: layer wheel callback' src/shell/plugin_layer/plugin_layer.cpp
      grep -Fq 'capture_keys' src/scripting/plugin_layer_config.cpp
      grep -Fq 'R39a: one hover snapshot' src/shell/bar/widgets/workspaces_widget.cpp
      grep -Fq 'workspaceWindowAssignments(it->output)' src/shell/bar/widgets/workspaces_widget.cpp
      grep -Fq 'item.activeDot->setHitTestVisible(false)' src/shell/bar/widgets/workspaces_widget.cpp
      grep -Fq 'R39a: never persist' src/shell/dock/dock.cpp
      grep -Fq 'R39a: select the requested action' src/shell/session/session_panel.cpp
      grep -Fq 'noctalia-system-menu' src/shell/panel/panel_manager.cpp
      grep -Fq 'm_selectionIndicator' src/shell/launcher/launcher_panel.cpp
      grep -Fq 'syncCompactControls()' src/shell/control_center/tabs/home_tab.cpp
      grep -Fq 'setCustomPalette(std::move(palette))' src/shell/control_center/tabs/home_tab.cpp
      grep -Fq 'fontWeightOptions.push_back({"650", "650"})' src/shell/settings/widget_settings_registry.cpp
      grep -Fq 'show_app_name' src/shell/bar/widgets/active_window_widget_definition.cpp
      grep -Fq 'title = app_identity::resolveRunningDesktopEntry(appId, desktopEntries()).name' src/shell/bar/widgets/active_window_widget.cpp
      grep -Fq 'gpu_only_nvidia' src/config/schema/config_schema.cpp
      grep -Fq 'pollCfg.gpuOnlyNvidia' src/system/system_monitor_service.cpp
      grep -Fq 'HUD27: short NVIDIA-only sampling sessions' src/system/system_monitor_service.cpp
      grep -Fq 'R41: a single 40px row' src/shell/lockscreen/lock_surface.cpp
      grep -Fq 'm_identityAvatar->setRadius(28.0F)' src/shell/lockscreen/lock_surface.cpp
      grep -Fq 'm_identityName->setHitTestVisible(false)' src/shell/lockscreen/lock_surface.cpp
      grep -Fq 'setAuthenticationFontSize(state.id' src/shell/lockscreen/lockscreen_widgets_host.cpp
      grep -Fq 'surfaceH < 700.0F' src/shell/lockscreen/lockscreen_widgets_host.cpp
    '';
  });

in
{
  imports = [
    inputs.noctalia.homeModules.default
    (import ./lockscreen-avatar.nix { inherit avatar; })
  ];

  config = {
    xdg.dataFile."applications/nvim.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Neovim
      Comment=Terminal text editor
      Exec=kitty --class=Neovim nvim
      Icon=utilities-terminal
      Terminal=false
      Categories=Development;TextEditor;
      StartupWMClass=Neovim
    '';

    # HM owns this one symlink; user pictures stay outside the store and Git.
    home = {
      file."Pictures/Wallpapers/managed".source = wallpapers.directory;
      activation.wallpaperLocalDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        local_wallpapers=${lib.escapeShellArg "${wallpaperRoot}/local"}
        if [ -e "$local_wallpapers" ] || [ -L "$local_wallpapers" ]; then
          if [ ! -d "$local_wallpapers" ]; then
            echo "Wallpapers/local exists and is not a directory; preserving it" >&2
            exit 1
          fi
        else
          run mkdir -p -- "$local_wallpapers"
        fi
      '';

      # Native notify-send remains available for desktop notification review.
      packages = [ pkgs.libnotify ];
    };

    programs.noctalia = {
      enable = true;
      package = noctaliaPackage;

      systemd.enable = true;
      customPalettes.onedark = {
        dark = {
          mPrimary = palette.blue;
          mOnPrimary = palette.black;
          mSecondary = palette.cyan;
          mOnSecondary = palette.black;
          mTertiary = palette.purple;
          mOnTertiary = palette.black;
          mError = palette.red;
          mOnError = palette.black;
          mSurface = palette.bg;
          mOnSurface = palette.brightFg;
          mSurfaceVariant = palette.surface;
          mOnSurfaceVariant = palette.fg;
          mOutline = palette.border;
          mShadow = palette.black;
          mHover = palette.selection;
          mOnHover = palette.brightFg;
          terminal = {
            background = palette.bg;
            foreground = palette.fg;
            cursor = palette.brightFg;
            cursorText = palette.bg;
            selectionBg = palette.selection;
            selectionFg = palette.brightFg;
            normal = {
              inherit (palette) black;
              inherit (palette) red;
              inherit (palette) green;
              inherit (palette) yellow;
              inherit (palette) blue;
              magenta = palette.purple;
              inherit (palette) cyan;
              white = palette.fg;
            };
            bright = {
              black = palette.border;
              inherit (palette) red;
              inherit (palette) green;
              inherit (palette) yellow;
              inherit (palette) blue;
              magenta = palette.purple;
              inherit (palette) cyan;
              white = palette.brightFg;
            };
          };
        };
      };

      settings =
        (import ./noctalia/bar.nix {
          inherit palette;
        })
        // (import ./noctalia/plugins.nix {
          inherit pkgs;
        })
        // {
          shell = {
            lang = "zh-CN";
            font_family = palette.fonts.sans;
            settings_window_translucent = true;
            avatar_path = "${config.home.homeDirectory}/.face";
            corner_radius_scale = 4.0 / 3.0;
            # One outer outline, quieter cards, and distinct input boundaries.
            button_borders = false;
            card_borders = false;
            input_borders = true;
            popup_borders = true;
            popup_shadows = true;
            # Panels still close on Escape/outside click; keep the surfaces clear
            # of repeated close glyphs. Notifications remain dismissible by right-click.
            show_close_buttons = false;
            # Native history owns collection and persistence; no parallel
            # cliphist watchers. The X11/Wayland bridge is a separate service.
            clipboard_enabled = true;
            show_location = true;
            # Alt+Tab (keybinds.nix). Most-recently-used order like other
            # desktops, every window on every tag. Mango 0.18 has no toplevel
            # image capture, so cards show application icons.
            window_switcher = {
              style = "carousel";
              mru = true;
              show_all_outputs = true;
              current_workspace_only = false;
              show_caption = true;
              show_count = true;
              show_app_icon = true;
            };
            # New in noctalia 5.2.1: readline-style editing (Ctrl+A/E/U/K) in
            # the shell's own text inputs.
            readline_shortcuts = true;

            animation = {
              enabled = !reducedMotion;
              speed = 1.0;
            };
            launch_apps_as_systemd_services = true;

            shadow = {
              direction = "down";
              alpha = 0.32;
            };

            panel = {
              # Native shared Soft surface; do not alter bar/Dock/plugin styling.
              transparency_mode = panelSurface.mode;
              borders = true;
              border_color = "outline_variant";
              border_width = 1;
              # Client shadow plus Mango layer blur produces an opaque fringe.
              inherit (panelSurface) shadow;
              launcher_placement = "floating";
              clipboard_placement = "floating";
              control_center_placement = "floating";
              launcher_position = "center";
              control_center_position = "top_right";
              open_near_click_launcher = false;
              open_near_click_control_center = false;
              floating_offset = 12;
              # Hover/selection provides the row emphasis without a card per row.
              list_item_background = false;
              wallpaper_placement = "floating";
              wallpaper_position = "center";
              session_placement = "attached";
            };

            launcher = {
              # v5.3's rebuilt full layout; `simple` retains the older compact UI.
              layout = "full";
              width = 520;
              search_position = "top";
              default_view = "pinned";
              categories = true;
              category_icons_only = true;
              show_icons = true;
              # Keep full rows so application/provider descriptions and paths
              # remain visible; the locked UI has no separate row-density knob.
              compact = false;
              app_grid = false;
              show_app_actions = true;
              track_usage = true;
              sort_by_usage = true;
              pinned = [
                # Noctalia resolves pinned values against DesktopEntry::id,
                # which is the filename stem (without the .desktop suffix).
                "kitty"
                "nvim"
                "firefox"
                "thunar"
              ];
              # calculator-plus is removed. The built-in provider has no enable
              # switch; exclude it from ordinary search. Its explicit /calc
              # prefix remains available (an empty prefix restores that default).
              providers.calculator.global = false;
            };

            # Preserve application-provided color icons in the launcher. The
            # pinned Noctalia defaults this to false; set it explicitly so a
            # prior user setting cannot grayscale the icon list.
            app_icon_colorize = false;

            screen_corners = {
              enabled = false;
              size = 12;
            };

            # Noctalia's built-in polkit authentication agent (the password
            # prompt for privileged actions). security.polkit.enable is already on
            # system-side and mango runs no other polkit agent, so letting Noctalia
            # be that agent does not conflict with anything.
            polkit_agent = true;
          };

          theme = {
            mode = "dark";
            shell_mode = "follow";
            # Shell theme changes must not rewrite GNOME's color-scheme preference.
            sync_color_scheme = false;
            source = "custom";
            custom_palette = "onedark";
            pure_black_dark = false;

            templates = {
              enable_builtin_templates = true;
              enable_community_templates = true;
              user = lib.optionalAttrs (builtins.elem "firefox" noctaliaIntegrations) {
                noctalia-firefox = {
                  input_path = "${integrationTemplates.firefox.templateFile}";
                  output_path = "$XDG_CACHE_HOME/noctalia/firefox/userChrome.css";
                  post_hook = "${pkgs.writeShellScript "noctalia-firefox-theme-apply" ''
                    exec ${pkgs.python3}/bin/python3 ${integrationTemplates.firefox.hookDirectory}/apply-noctalia-userChrome.py "''${XDG_CACHE_HOME:-$HOME/.cache}/noctalia/firefox/userChrome.css"
                  ''}";
                  hook_async = false;
                };
              };
              builtin_ids = lib.optional (builtins.elem "btop" noctaliaIntegrations) "btop" ++ [
                "gtk3"
                "gtk4"
                "qt"
              ];
              community_ids = builtins.filter (id: builtins.elem id noctaliaIntegrations) [
                "obsidian"
                "vscode"
                "yazi"
                "zathura"
              ];
            };
          };

          desktop_widgets.enabled = false;

          wallpaper = {
            enabled = true;
            directory = wallpaperRoot;
            fill_mode = "crop";
            fill_color = "surface";
            transition_on_startup = !reducedMotion;
            transition = lib.optional (!reducedMotion) "fade";
            transition_duration = 450;
            default.path = defaultWallpaperPath;
            automation = {
              enabled = true;
              interval_seconds = 86400;
              pause_on_fullscreen = true;
              order = "random";
              recursive = true;
            };
          };

          backdrop = {
            enabled = false;
            blur_intensity = 0.40;
            tint_intensity = 0.50;
          };

          audio = {
            enable_overdrive = true;
            enable_sounds = true;
          };

          brightness = {
            enable_ddcutil = true;
            minimum_brightness = 0.05;
            monitor.${desktop.primaryOutput}.backend = "backlight";
          };

          battery = {
            warning_threshold = 20;
          };

          # Keep the launcher corner away from the centered Dock reveal strip.
          # action only accepts none / launcher / control_center / window_switcher
          # / command (hotCornerActionSelect in settings_registry.cpp); note it is
          # a free-form string in the schema, so a typo passes validation and then
          # silently does nothing at runtime.
          hot_corners = {
            enabled = true;
            delay_ms = 200; # dwell time, so a cursor merely passing by does not fire it
            bottom_left.action = "launcher";
            bottom_right.action = "none";
            top_left.action = "none";
            top_right.action = "none";
          };

          # No automatic or forced color-temperature changes.
          nightlight = {
            enabled = false;
            force = false;
            temperature_day = 6500;
            temperature_night = 4000;
          };

          weather = {
            enabled = true;
            unit = "metric";
            effects = !reducedMotion;
          };

          system.monitor = {
            enabled = true;
            gpu_poll_seconds = 2.0;
            gpu_only_nvidia = (hostFacts.gpu or { }) ? nvidiaBusId;
          };

          location = {
            auto_locate = true;
            address = "Jingkou Qu, China";
          };

          notification = {
            enable_daemon = true;
            show_app_name = true;
            show_actions = true;
            position = "top_right";
            layer = "overlay";
            width = 320;
            offset_x = 16;
            offset_y = 12;
            max_visible = 3;
            border = true;
            border_color = "outline_variant";
            border_width = 1;
            background_opacity = panelSurface.opacity;
            # Keep transient messages on the output currently being used.
            follow_focused_output = true;
          };

          osd = {
            # Keep transient feedback above the revealed floating Dock.
            position = "bottom_center";
            orientation = "horizontal";
            offset_y = 96;
            hide_delay_ms = 1400;
            border = true;
            border_color = "outline_variant";
            border_width = 1;
            background_opacity = panelSurface.opacity;
            follow_focused_output = true;
          };

          idle = {
            pre_action_fade_seconds = 3.0;
            behavior = {
              lock = {
                enabled = true;
                timeout = 900;
                action = "lock";
              };
              screen-off = {
                enabled = true;
                timeout = 1800;
                action = "screen_off";
              };
              suspend = {
                enabled = true;
                timeout = 3600;
                action = "lock_and_suspend";
              };
            };
          };

          hooks = {
            session_locked = [ "${pkgs.playerctl}/bin/playerctl pause" ];
            battery_discharging = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver";
            battery_charging = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance";
            battery_percentage_changed = "${lowBatterySuspend}";
          };

          control_center = {
            # Compact navigation exposes System, Power, Monitor and Notifications.
            sidebar = "none";
            # Direct section entry keeps a compact icon rail for navigation.
            sidebar_section = "compact";
            width = 348;
            show_shortcut_labels = true;
            circular_avatar = false;
            show_session_button = true;
            shortcuts = map (type: { inherit type; }) [
              "wifi"
              "bluetooth"
              "system"
              "power_profile"
              "caffeine"
              "notification"
            ];
          };

          lockscreen = {
            enabled = true;
            lock_before_suspend = true;
            # Lock/unlock has its own effect pool; it does not inherit wallpaper.
            transition = lib.optional (!reducedMotion) "fade";
            transition_duration = 200;
            edge_smoothness = 0.3;
            blur_intensity = 0.75;
            tint_intensity = 0.58;
            blurred_desktop = false;
          };

          lockscreen_widgets = {
            enabled = true;
            widget_order = [
              "lockscreen-widget-clock"
              "lockscreen-widget-date"
              "lockscreen-login-box@${desktop.primaryOutput}"
            ];
            widget = {
              "lockscreen-login-box@${desktop.primaryOutput}" = {
                type = "login_box";
                output = desktop.primaryOutput;
                cx = logicalWidth / 2;
                cy = logicalHeight * 0.58;
                box_width = 400.0;
                settings = {
                  layout = "compact";
                  show_media = false;
                  show_weather = false;
                  # These are lock-screen power actions, not login-session choices.
                  show_session_buttons = false;
                  show_unlock_hint = true;
                  show_caps_lock = true;
                  show_keyboard_layout = false;
                  show_password_reveal = true;
                  background_color = "surface_container";
                  background_opacity = 0.0;
                  background_radius = 16.0;
                  input_radius = 8.0;
                  input_opacity = 0.92;
                };
              };
              lockscreen-widget-clock = {
                type = "clock";
                output = desktop.primaryOutput;
                cx = logicalWidth / 2;
                cy = logicalHeight * 0.30;
                box_width = 288.0;
                box_height = 86.0;
                settings = {
                  format = "{:%H:%M}";
                  font_family = palette.fonts.sans;
                  center_text = true;
                  background = false;
                  color = "on_surface";
                  shadow = true;
                };
              };
              lockscreen-widget-date = {
                type = "clock";
                output = desktop.primaryOutput;
                cx = logicalWidth / 2;
                cy = logicalHeight * 0.36;
                box_width = 200.0;
                box_height = 22.0;
                settings = {
                  format = "{:%-m月%-d日 %A}";
                  font_family = palette.fonts.sans;
                  center_text = true;
                  background = false;
                  color = "on_surface";
                  shadow = true;
                };
              };
            };

          };
        };
    };

    # Keep Noctalia bound to the Mango session and enforce a bounded recovery
    # budget. The HM module owns the unit; these are field-level overrides.
    systemd.user.services.noctalia = {
      Unit = {
        # force: Replace upstream generic session dependencies with the Mango target.
        PartOf = lib.mkForce [ "mango-session.target" ];
        # force: Replace upstream generic session dependencies with the Mango target.
        After = lib.mkForce [ "mango-session.target" ];
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
        # Noctalia owns the ext-session-lock surface. Restarting it from an
        # activation while the session is locked abandons the lock and Mango
        # shows a solid fill that no password can clear. Config changes are
        # hot-reloaded; a new binary takes effect on the next login or an
        # explicit restart while unlocked. Home Manager's sd-switch honours
        # X-SwitchMethod (X-RestartIfChanged is NixOS-only and is ignored).
        X-SwitchMethod = "keep-old";
      };
      Service = {
        ExecStartPre = "${reconcileOverrides}";
        Restart = "on-failure";
        RestartSec = 2;
        UnsetEnvironment = [ "LC_ALL" ];
        Environment = (lib.mapAttrsToList (name: value: "${name}=${value}") safeSessionVariables) ++ [
          "LC_TIME=zh_CN.UTF-8"
        ];
      };
      # force: Replace upstream generic session dependencies with the Mango target.
      Install.WantedBy = lib.mkForce [ "mango-session.target" ];
    };
  };
}
