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

  distroLogo = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";

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
      ./noctalia/tech-osd-segments.patch
      ./noctalia/hud-bar.patch
      ./noctalia/hud-tooltips.patch
      ./noctalia/hud-battery.patch
      ./noctalia/hud-controls-tooltips.patch
      ./noctalia/hud-sysmon.patch
      ./noctalia/hud-balanced.patch
      ./noctalia/hud-drawer-clearance.patch
    ];
    # Fail the source build if an upstream rename or patch drift removes the
    # segmented OSD implementation instead of silently losing the appearance.
    postPatch = (old.postPatch or "") + ''
      grep -Fq 'm_selectionIndicator' src/shell/launcher/launcher_panel.cpp
      grep -Fq 'item.accent = static_cast<Box*>' src/shell/bar/widgets/workspaces_widget.cpp
      grep -Fq 'syncCompactControls()' src/shell/control_center/tabs/home_tab.cpp
      grep -Fq 'R31: flat One Dark surface' src/shell/bar/bar.cpp
      ! grep -Fq 'hudLineStyle(' src/shell/bar/bar.cpp
      grep -Fq 'R31: minimal reuses the indicator' src/shell/bar/widgets/workspaces_widget.cpp
      grep -Fq 'bg->setOpacity(run.accordionProgress)' src/shell/bar/bar.cpp
      grep -Fq 'HUD27: native faded separator' src/shell/bar/widgets/spacer_widget.cpp
      grep -Fq 'minimum_visible' src/shell/bar/widgets/workspaces_widget_definition.cpp
      grep -Fq 'HUD27: keep the first N labels' src/shell/bar/widgets/workspaces_widget.cpp
      grep -Fq 'HUD27b: mode name belongs in the tooltip' src/shell/bar/widgets/power_profile_widget.cpp
      grep -Fq 'rootNode->setSize(m_glyph->width(), m_glyph->height())' src/shell/bar/widgets/power_profile_widget.cpp
      grep -Fq 'panel.summary = available ? profile' src/shell/bar/widgets/power_profile_widget.cpp
      grep -Fq 'kHudCenterClearance = 24.0F' src/shell/bar/bar.cpp
      grep -Fq 'instance.endSection->width() > endSlotMain' src/shell/bar/bar.cpp
      grep -Fq 'HUD27b: a single bounded second pass' src/shell/bar/bar.cpp
      grep -Fq 'setDrawerCompact(false)' src/shell/bar/bar.cpp
      grep -Fq 'setDrawerCompact(true)' src/shell/bar/bar.cpp
      grep -Fq 'm_compactDot->setVisible(m_drawerCompact)' src/shell/bar/widgets/sysmon_widget.cpp
      grep -Fq 'HUD27: display panel uses friendly metadata' src/shell/bar/widgets/brightness_widget.cpp
      grep -Fq 'display.friendlyName' src/system/brightness_service.cpp
      grep -Fq 'out->refreshMilliHz = refresh' src/wayland/wayland_connection.cpp
      grep -Fq 'HUD27: structured tooltip payload' src/shell/tooltip/tooltip_content.h
      grep -Fq 'HUD27' src/shell/tooltip/tooltip_manager.cpp
      grep -Fq 'hide_unavailable' src/shell/bar/widgets/sysmon_widget_definition.cpp
      grep -Fq 'show_gpu_temperature' src/shell/bar/widgets/sysmon_widget_definition.cpp
      grep -Fq 'label_outside' src/shell/bar/widgets/battery_widget_definition.cpp
      grep -Fq 'HUD27: inset the green fill' src/shell/bar/widgets/battery_widget.cpp
      grep -Fq 'HUD27: initialize rebuilt marks' src/shell/bar/widgets/workspaces_widget.cpp
      grep -Fq 'HUD27: materialize pinned numeric labels' src/shell/bar/widgets/workspaces_widget.cpp
      grep -Fq 'HUD27: keep peripheral charge rows' src/shell/bar/widgets/battery_widget.cpp
      grep -Fq 'HUD27: retain live audio-device details' src/shell/bar/widgets/volume_widget.cpp
      grep -Fq 'HUD27: preserve the live provider' src/shell/bar/widgets/network_widget.cpp
      grep -Fq 'HUD27: preserve each connected device' src/shell/bar/widgets/bluetooth_widget.cpp
      grep -Fq 'HUD27: short NVIDIA-only sampling sessions' src/system/system_monitor_service.cpp
      grep -Fq 'HUD27: give the selected bar tools readable headings' src/shell/bar/widgets/plugin_widget.cpp
      grep -Fq 'tooltipRowKeyLimit(renderer, row' src/shell/tooltip/tooltip_manager.cpp
      grep -Fq 'gpu_only_nvidia' src/config/schema/config_schema.cpp
      grep -Fq 'pollCfg.gpuOnlyNvidia' src/system/system_monitor_service.cpp
      grep -Fq 'm_graph->setColor(m_highlightColor)' src/shell/bar/widgets/sysmon_widget.cpp
      grep -Fq 'HUD27b: external percentages reserve' src/shell/bar/widgets/battery_widget.cpp
      grep -Fq 'temperature_hide_below'  src/shell/bar/widgets/sysmon_widget_definition.cpp
      grep -Fq 'HUD27b: CPU alert is hidden below 80; orange at 80, red at 90.' src/shell/bar/widgets/sysmon_widget.cpp
      grep -Fq 'currentStats.cpuTempC.value_or(0.0) >= m_temperatureHideBelow' src/shell/bar/widgets/sysmon_widget.cpp
      grep -Fq 'addMetric(SysmonStat::GpuVram, "VRAM"' src/shell/bar/widgets/sysmon_widget.cpp
      grep -Fq 'addMetric(SysmonStat::GpuTemp, "独显温度"' src/shell/bar/widgets/sysmon_widget.cpp
      grep -Fq 'HUD27b: SYSTEM owns live GPU temperature and VRAM' src/shell/bar/widgets/sysmon_widget.cpp
      grep -Fq 'HUD27b: fixed-width value boxes' src/shell/bar/widgets/sysmon_widget.cpp
      grep -Fq 'CountdownRingNode'  src/shell/bar/widgets/sysmon_widget.cpp
      grep -Fq 'UI4: lockscreen palette-gradient password underline and cached runtime status' src/shell/lockscreen/lock_surface.cpp
      grep -Fq 'lockscreenRuntimeStatus()' src/shell/lockscreen/lock_surface.cpp
      grep -Fq 'charge_control_end_threshold' src/shell/lockscreen/lock_surface.cpp
      grep -Fq 'UI4: ideapad_acpi conservation status precedes the standard battery limit fallback' src/shell/lockscreen/lock_surface.cpp
      grep -Fq 'm_passwordUnderline->setSize' src/shell/lockscreen/lock_surface.cpp
      grep -Fq 'm_passwordGlow->setHitTestVisible(false)' src/shell/lockscreen/lock_surface.cpp
      grep -Fq 'm_passwordUnderline->setHitTestVisible(false)' src/shell/lockscreen/lock_surface.cpp
      grep -Fq 'label.setHitTestVisible(false)' src/shell/lockscreen/lock_surface.cpp
      grep -Fq 'UI4: palette-surface separators create twenty compact ticks' src/shell/osd/osd_overlay.cpp
      grep -Fq 'UI4: clear non-owning tick pointers before rebuilding their owning scene tree' src/shell/osd/osd_overlay.cpp
      grep -Fq 'progressTicks' src/shell/osd/osd_overlay.h
      grep -Fq 'progressTicks.size()' src/shell/osd/osd_overlay.cpp
      grep -Fq 'separator->setHitTestVisible(false)' src/shell/osd/osd_overlay.cpp
      grep -Fq 'setFontFamily("monospace")' src/shell/osd/osd_overlay.cpp
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

      # External dependencies declared by the enabled plugins that this machine
      # would otherwise be missing. Plugins never install their own dependencies
      # and just silently do nothing when one is absent -- no error, no hint.
      # Keep this in sync when adding or removing plugins; every entry maps to
      # one specific plugin.
      packages = with pkgs; [
        tmuxp # tmux-provider (tmux itself lives in tmux.nix)
        libnotify # notify-send for desktop notification review
        nix-search-tv # nix-search community launcher provider
        fzf # nix-search community launcher provider
      ];

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
          inherit palette distroLogo;
        })
        // (import ./noctalia/plugins.nix {
          inherit inputs pkgs;
        })
        // {
          shell = {
            lang = "zh-CN";
            font_family = palette.fonts.sans;
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
              # Reading surfaces stay opaque: Mango layer blur is deliberately
              # off, so transparency would expose sharp application text behind.
              transparency_mode = "solid";
              borders = true;
              border_color = "outline_variant";
              border_width = 1;
              shadow = true;
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
              wallpaper_placement = "attached";
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
              compact = false;
              # List rows retain long names and descriptions; provider search,
              # pinned apps, categories and desktop actions remain available.
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
              enabled = true;
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

          # Put triggers in the bottom corners, away from the top bar's hover
          # area. The bottom edge is free while the dock is off.
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

          # force = false keeps the shift to night-time only instead of locking
          # the temperature all day.
          nightlight = {
            enabled = true;
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
            offset_y = 64;
            max_visible = 3;
            border = true;
            border_color = "outline_variant";
            border_width = 1;
            background_opacity = 0.98;
            # Keep transient messages on the output currently being used.
            follow_focused_output = true;
          };

          osd = {
            # Separate transient device feedback from notifications/control center.
            position = "bottom_center";
            orientation = "horizontal";
            offset_y = 32;
            hide_delay_ms = 1400;
            border = true;
            border_color = "outline_variant";
            border_width = 1;
            background_opacity = 0.98;
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

          # Off: the bar already carries a launcher and workspaces, so the dock is
          # a duplicate entry point. With it off every other dock.* key is
          # meaningless, hence the single line.
          dock.enabled = false;

          control_center = {
            # The local layout patch keeps Home at 380px without a sidebar.
            sidebar = "none";
            # Direct section entry keeps a compact icon rail for navigation.
            sidebar_section = "compact";
            width = 380;
            show_shortcut_labels = true;
            circular_avatar = false;
            show_session_button = true;
            shortcuts = map (type: { inherit type; }) [
              "wifi"
              "bluetooth"
              "notification"
              "caffeine"
              "nightlight"
              "power_profile"
            ];
          };

          lockscreen = {
            enabled = true;
            # Lock/unlock has its own effect pool; it does not inherit wallpaper.
            transition = lib.optional (!reducedMotion) "fade";
            transition_duration = 200;
            edge_smoothness = 0.3;
            blur_intensity = 0.40;
            tint_intensity = 0.48;
            blurred_desktop = false;
          };

          lockscreen_widgets = {
            enabled = true;
            widget_order = [
              "lockscreen-widget-clock"
              "lockscreen-widget-seconds"
              "lockscreen-widget-date"
              "lockscreen-login-box@${desktop.primaryOutput}"
            ];
            widget = {
              "lockscreen-login-box@${desktop.primaryOutput}" = {
                type = "login_box";
                output = desktop.primaryOutput;
                cx = logicalWidth / 2;
                cy = logicalHeight * 0.54;
                settings = {
                  layout = "compact";
                  show_media = false;
                  show_weather = false;
                  # These are lock-screen power actions, not login-session choices.
                  show_session_buttons = false;
                  show_unlock_hint = true;
                  show_caps_lock = true;
                  show_keyboard_layout = true;
                  show_password_reveal = true;
                  background_color = "surface_container";
                  background_opacity = 1.0;
                  background_radius = 16.0;
                  input_radius = 8.0;
                  input_opacity = 1.0;
                };
              };
              lockscreen-widget-clock = {
                type = "clock";
                output = desktop.primaryOutput;
                cx = logicalWidth / 2;
                cy = logicalHeight * 0.24;
                box_width = 420.0;
                box_height = 110.0;
                settings = {
                  format = "{:%H:%M}";
                  font_family = palette.fonts.mono;
                  center_text = true;
                  background = false;
                  color = "on_surface";
                  shadow = true;
                };
              };
              # A separate, smaller clock keeps seconds visually subordinate
              # while retaining the clock widget's native second-tick updates.
              lockscreen-widget-seconds = {
                type = "clock";
                output = desktop.primaryOutput;
                cx = logicalWidth / 2 + 128;
                cy = logicalHeight * 0.24 + 17;
                box_width = 48.0;
                box_height = 42.0;
                settings = {
                  format = "{:%S}";
                  font_family = palette.fonts.mono;
                  center_text = true;
                  background = false;
                  color = "outline_variant";
                  shadow = false;
                };
              };
              lockscreen-widget-date = {
                type = "clock";
                output = desktop.primaryOutput;
                cx = logicalWidth / 2;
                cy = logicalHeight * 0.325;
                box_width = 360.0;
                box_height = 32.0;
                settings = {
                  format = "{:%Y年%m月%d日  %A}";
                  font_family = palette.fonts.mono;
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
      };
      Service = {
        ExecStartPre = "${reconcileOverrides}";
        Restart = "on-failure";
        RestartSec = 2;
        Environment = (lib.mapAttrsToList (name: value: "${name}=${value}") safeSessionVariables) ++ [
          "LC_TIME=zh_CN.UTF-8"
        ];
      };
      # force: Replace upstream generic session dependencies with the Mango target.
      Install.WantedBy = lib.mkForce [ "mango-session.target" ];
    };
  };
}
