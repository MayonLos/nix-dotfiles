{
  pkgs,
  inputs,
  ...
}:

let
  wallpaperDir = "${../../_assets/wallpaper}";
  defaultWallpaperPath = "${../../_assets/wallpaper/wallpaper-001.png}";

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

  # Upstream bug workaround, in the same spirit as the mark-shot patch in
  # programs/apps/screenshot.nix: a plugin's code lives in a read-only store
  # path and there is no override hook, so the source tree is copied and one
  # file repaired.
  #
  # quill 1.1.0's nextDueInMs() assigns
  #     nextDueCache.value = soonest and (now + soonest) or nil
  # and then returns `nextDueCache.value - now` unguarded (service.luau:119).
  # With no todo that has BOTH a due date and a time still in the future,
  # `soonest` stays nil, so the subtraction throws on every service tick;
  # noctalia then disables the entry for erroring too often ("fel/quill:index
  # 因错误过多已被禁用"), and a disabled index is also why the Ask tab replies
  # that it has no notes in context. A fresh, empty vault is exactly this case,
  # so the plugin does not work out of the box.
  #
  # The cached early return carried the mirror-image defect: it hands back the
  # absolute due instant where its only caller (service.luau:305) compares the
  # result against 60000 to choose the tick length, so a warm cache never
  # engaged the finer tick and a reminder could be up to poll_interval_ms late.
  # Repaired to return the remaining duration, like the fresh path.
  #
  # Upstream main still carries both lines, so this is not "wait for a
  # release". --replace-fail rather than --replace: if upstream rewrites or
  # fixes the file, the build stops here loudly, which is the moment to delete
  # this derivation instead of keeping a patch that no longer matches.
  patchedCommunityPlugins = pkgs.runCommand "noctalia-plugins-community-patched" { } ''
    cp -r ${inputs.noctalia-plugins-community} $out
    chmod -R u+w $out

    substituteInPlace $out/quill/service.luau \
      --replace-fail '  return nextDueCache.value - now' \
      '  return nextDueCache.value and (nextDueCache.value - now) or nil' \
      --replace-fail '    return nextDueCache.value' \
      '    return nextDueCache.value - now'
  '';
in
{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  config = {
    # External dependencies declared by the enabled plugins that this machine
    # would otherwise be missing. Plugins never install their own dependencies
    # and just silently do nothing when one is absent -- no error, no hint.
    # Keep this in sync when adding or removing plugins; every entry maps to
    # one specific plugin.
    home.packages = with pkgs; [
      tmuxp # tmux-provider (tmux itself lives in tmux.nix)
    ];

    programs.noctalia = {
      enable = true;
      package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;

      systemd.enable = false;

      settings = {
        shell = {
          lang = "zh-CN";
          font_family = "Noto Sans CJK SC";
          corner_radius_scale = 1.0;
          clipboard_enabled = true;
          show_location = true;

          animation = {
            enabled = true;
            speed = 0.95;
          };

          shadow = {
            direction = "down";
            alpha = 0.55;
          };

          panel = {
            transparency_mode = "glass";
            borders = true;
            shadow = true;
            launcher_placement = "floating";
            clipboard_placement = "floating";
            control_center_placement = "attached";
            wallpaper_placement = "attached";
            session_placement = "attached";
          };

          launcher = {
            categories = true;
            show_icons = true;
            compact = true;
            app_grid = true;
            sort_by_usage = true;
          };

          screen_corners = {
            enabled = true;
            size = 32;
          };

          # Noctalia's built-in polkit authentication agent (the password
          # prompt for privileged actions). security.polkit.enable is already on
          # system-side and mango runs no other polkit agent, so letting Noctalia
          # be that agent does not conflict with anything.
          polkit_agent = true;
        };

        theme = {
          mode = "auto";
          source = "builtin";
          builtin = "Tokyo-Night";

          templates = {
            enable_builtin_templates = true;
            enable_community_templates = true;
            builtin_ids = [
              "btop"
              "cava"
              "kitty"
              "gtk3"
              "gtk4"
              "mango"
              "qt"
            ];
            community_ids = [
              "obsidian"
              "vscode"
              "yazi"
              "zathura"
              "zen-browser"
            ];
          };
        };

        # kind = "path" rather than "git": noctalia treats a Path source as a
        # read-only immutable directory (config_types.h says so verbatim, "e.g.
        # a Nix store path"), reads location directly at startup, and never
        # clones or touches the network -- update/auto_update are no-ops.
        #
        # That is a hard requirement on this machine: a git source clones during
        # startup, and when github is unreachable it burns the whole timeout and
        # then segfaults, taking down the noctalia that mango autostarts -- which
        # is why both sources used to sit at enabled = false. Store paths remove
        # that failure mode and pin the versions in flake.lock; updates go
        # through nix flake update like everything else.
        plugins = {
          # Enum since noctalia 5: all | official | none. A boolean is still
          # accepted but warns as deprecated at startup.
          auto_update = "none";

          source = [
            {
              name = "official";
              kind = "path";
              location = "${inputs.noctalia-plugins-official}";
              enabled = true;
            }
            {
              name = "community";
              kind = "path";
              # Patched copy of the input, not the input itself: quill 1.1.0
              # ships a crash that disables its own index service. See
              # patchedCommunityPlugins in the let block above for the two
              # repaired lines and the conditions under which to drop this.
              location = "${patchedCommunityPlugins}";
              enabled = true;
            }
            # No local source. `_plugins/ask` (an LLM chat panel) was the only
            # thing in it and was removed on 2026-09-18; a path source pointing
            # at a directory that no longer exists fails evaluation, so the
            # whole block goes with it. To add one back: create
            # `_plugins/<name>/plugin.toml` and restore this entry -- with no
            # catalog.toml a path source just scans the directory
            # (plugin_catalog.cpp:272).
          ];

          # WARNING: this list is shadowed by the runtime override layer.
          # Toggling a plugin in Noctalia's settings UI writes the entire enabled
          # array into ~/.local/state/noctalia/settings.toml, which takes
          # priority -- once the GUI has touched it, nothing written here has any
          # effect. To hand control back, drop the [plugins] section from the
          # override layer and run `noctalia msg config-reload`. The other way
          # round, `noctalia config export merged` prints the effective values so
          # whatever you settled on in the GUI can be copied back here.
          #
          # Deliberately excluded: battery-threshold (needs sudo/groupadd/usermod
          # to change system permissions), compositor animations (writes to the
          # read-only HM symlink), screen-toolkit / color_picker /
          # keybind-cheatsheet (depend on hyprpicker and hyprctl, Hyprland only),
          # translator (goes through Google Translate, unreachable here).
          enabled = [
            "3ri4ng0ld/ip-monitor"
            "8bury/mini-docker"
            "cleboost/jetbrains-provider"
            "dunarand/tmux-provider"
            "noctalia/kaomoji"
            "radimous/prismlauncher-instances"
            "rxtsel/portctl"
            "whyoolw/sharednd"

            # Added 2026-09-25. Every dependency below was checked with
            # `command -v` on this host rather than taken from the plugin's own
            # claim; noctalia never installs a dependency and a missing one
            # fails silently, with no error and no hint.
            #
            # The only entry that needed a new package is fel/ocr (tesseract,
            # added in ../../packages.nix). The rest resolve against what is
            # already on PATH: mmsg and jq ship with mango / the CLI set.
            "coder/deepseek_usage" # DeepSeek balance; needs its API key in the GUI, see below
            "ezequiel/mango_layouts" # jq + mmsg
            "fel/ocr" # grim + slurp + tesseract
            # Replaces noctalia/notes, removed below. Same slot in
            # group:panels, but the notes are plain Markdown on disk (any
            # editor, git, Obsidian), there is a launcher entry (/nt), and the
            # optional AI backend defaults to the opencode CLI, which is
            # already on PATH. Core notes and todos need no dependency at all;
            # `git` is only for its opt-in history feature.
            "fel/quill"
            "gambled23/mangowm-keymode" # mmsg; shows the keymode SUPER+SHIFT,R enters
            "mindnbytes/nix-status" # nix + readlink; flake_dir set in plugin_settings

            # Removed, with the reason recorded rather than lost. To restore any
            # of them, re-add its id here and, where it had one, its
            # `<id>:<entry>` string to the matching capsule group below.
            #
            # 2026-09-27
            #   noctalia/notes 1.0.5 — superseded by fel/quill above, not broken.
            #     quill takes the same panel slot while keeping the notes as
            #     plain Markdown in a directory it does not otherwise own. No
            #     migration was needed: the folder notes had been writing to
            #     (~/Documents/Notes) contained no files.
            #   nightwatch75/todo 1.2.1 — same reason, one step later: quill's
            #     Todos tab covers `- [ ]` items in the same vault, so keeping a
            #     second task list only split them across two stores. Its seven
            #     open tasks were moved into ~/notes/Inbox.md first (all except
            #     `mp157`, which quill already had); ~/Documents/Todo/todo.json
            #     is left untouched, so the removal loses nothing.
            #
            # 2026-09-25, all three after being measured rather than guessed at.
            #
            #   weinguyen/opencode-companion 0.2.0 — auto-started `opencode
            #     serve` on 127.0.0.1:4096 and added a chat panel, but the panel
            #     only duplicated what the terminal already does.
            #   fel/agent-glow 0.1.0 — the watcher itself ran fine, but it has
            #     no codex collector at all: activity.py implements
            #     collect_claude and collect_opencode only, and every other
            #     family falls back to "CPU >= 15%". Measured during an active
            #     codex turn (confirmed by `systemd-inhibit --who codex --why
            #     "Codex is running an active turn"`), the probe still reported
            #     codex: 0.0 — codex blocks on the API with almost no CPU. Since
            #     codex and dsh are what actually runs here, the indicator could
            #     never light up.
            #   mdj2812/mihomo-control 0.2.0 — host/port/secret are ordinary
            #     settings, but there is nothing to connect to: verge-mihomo
            #     runs with external-controller = '' (verge.yaml also has
            #     enable_external_controller: false) and listens only on
            #     external-controller-unix, while the plugin speaks host:port.
          ];

          # Settings live in `plugin_settings` below, not under this table: the
          # generated config.toml carries only auto_update, enabled and
          # [[source]] here. One entry above still has no working declarative
          # route, for a reason rather than an oversight:
          #
          #   deepseek_usage    api_key. Deliberately NOT wired to
          #                     /run/secrets/deepseek-api-key: the plugin reads
          #                     its key only through noctalia.getConfig("api_key")
          #                     and has no file or environment indirection, so the
          #                     key has to be pasted into the GUI and ends up in
          #                     noctalia's plaintext state file. The sops copy and
          #                     that copy are independent; rotate both, or drop
          #                     this plugin.
          #
          #                     That state file is mode 644, which looks alarming
          #                     next to /run/secrets/* at 400 — but it is not
          #                     reachable: /home/mayon is 700 and mayon is the
          #                     only human account on this host (the nixbld*
          #                     uids are build sandboxes with no login). The key
          #                     is also already exported as DEEPSEEK_API_KEY into
          #                     every interactive shell by ../../shell/zsh.nix,
          #                     i.e. readable from /proc/<pid>/environ by anything
          #                     running as mayon — a strictly wider surface than
          #                     one more 600-equivalent file here. Accepted.
          #                     What it does cost is a second place to rotate.
          #
          # Setting those cards writes noctalia's runtime override layer, which
          # takes priority over this file — see the WARNING above.
        };

        # Per-plugin settings. This is a TOP-LEVEL table, a sibling of
        # `plugins` and `bar`, not a child of `plugins`: config_export.cpp:370
        # writes it as `plugin_settings` and settings_content_plugins.cpp:645
        # reads the path `{"plugin_settings", pluginId, key}`. A plugin's own
        # `[[setting]]` keys go here; its `[[widget.setting]]` keys belong under
        # `widget."<plugin-id>:<entry-id>"` instead (see the note in bar.main).
        #
        # Only settings that are safe to state declaratively live here. Secrets
        # do not: noctalia only reads a plugin's config value, never a file, so
        # anything secret would have to be written into this store path.
        plugin_settings = {
          # Without these the plugin loads but reports nothing usable: its
          # flake_dir defaults to empty and it then has no repository to
          # evaluate. `nixos_configuration` is the attribute under
          # nixosConfigurations, which is `nixos-btw` here.
          "mindnbytes/nix-status" = {
            flake_dir = "/home/mayon/nix-dotfiles";
            nixos_configuration = "nixos-btw";
          };

          # Default is "eng"; tesseract is built with chi_sim as well (see
          # ../../packages.nix), and the plugin passes this straight to
          # `tesseract -l`. Without it, Chinese screen text comes back empty.
          "fel/ocr".languages = "eng+chi_sim";

          # quill's default provider is "OpenCode Go", which needs an API key of
          # its own. The CLI provider instead drives the `opencode` binary that
          # llm-agents.nix already installs, so the AI features (capture,
          # summarize, ask over the notes) work with no key and no extra setup.
          # `off` would also be reasonable -- the notes, todos, launcher entry
          # and natural-language due dates all work without any AI -- but then
          # "AI capture" silently degrades to appending raw text.
          #
          # The model MUST be provider-qualified. quill's default,
          # deepseek-v4-flash, is an OpenCode Go model name, and ai.luau's
          # runCli() prefixes any model without a "/" with "opencode-go/" --
          # so leaving the default here runs
          #   opencode run --model opencode-go/deepseek-v4-flash ...
          # which answers with "UnknownError: Unexpected server error" in the
          # panel. `opencode models` lists the real ids; deepseek/deepseek-flash
          # was verified end to end against this host's opencode.
          "fel/quill" = {
            ai_backend = "opencode-cli";
            ai_model = "deepseek/deepseek-flash";
          };

          # mango_layouts declares `position = "bottom_right"` in its own
          # [[panel]] block, which is why it opened as a floating box in the
          # corner. Panel shell settings are per-panel and overridable from
          # here as `<panel-entry-id>_<key>` (panelShellSettingKey in
          # plugin_panel_shell.cpp): placement, position, layer, open_near_click.
          #
          # `position` only applies while floating, so it is the attached pair
          # that actually moves it: the panel now drops from the bar icon like
          # the other panel plugins instead of floating in a corner. Swap to
          # `panel_placement = "floating"` + a `panel_position` such as "center"
          # for the other shape.
          "ezequiel/mango_layouts" = {
            panel_placement = "attached";
            panel_position = "auto";
            panel_open_near_click = true;
          };
        };

        bar.main = {
          position = "top";
          thickness = 30;
          background_opacity = 0.88;
          radius = 16;
          margin_ends = 8;
          margin_edge = 6;
          padding = 8;
          widget_spacing = 6;
          shadow = true;
          contact_shadow = true;
          capsule = true;
          capsule_opacity = 0.96;

          # A plugin widget is spelled `<plugin-id>:<entry-id>` in the bar:
          # widget_factory.cpp hands the string straight to
          # PluginRegistry::resolve(), which splits it on the first colon into
          # manifest.id + entry.id (plugin_registry.cpp:20
          # `manifest->id + ":" + entry->id`). The entry-id comes from the
          # [[widget]] id in each plugin's plugin.toml, not from the plugin name;
          # "bar", "widget" and "status" are common, and collisions across
          # plugins are perfectly normal.
          #
          # Context and everyday tools on the left, clock in the center, system
          # status on the right.
          #
          # The panels group goes into start as a whole: all three are "click to
          # open a panel" tools, handy on the left, and start is left-aligned and
          # grows rightwards with room to spare -- unlike end, which is
          # right-aligned and clips from its leftmost item on overflow (that is
          # how the notes widget -- since replaced by fel/quill -- went missing).
          start = [
            "launcher"
            "workspaces"
            "media"
            "group:panels"
            "group:dev"
          ];
          center = [ "clock" ];
          # Four capsules on each side. `end` used to carry six -- the sys
          # group plus sysmon, tray, power_profile, battery and control-center
          # each in a capsule of its own, against four on the left, which made
          # the right half read as a row of loose pills rather than as groups.
          # sysmon, power_profile and battery are one subject (how much the
          # machine is working and what it is running on), so they became one.
          end = [
            "group:sys"
            "tray"
            "group:power"
            "control-center"
          ];

          capsule_group = [
            {
              id = "panels";
              members = [
                "fel/quill:status" # Markdown notes + todos; replaced noctalia/notes
                "8bury/mini-docker:mini-docker" # Docker management
                "rxtsel/portctl:indicator" # inspect and kill port listeners
              ];
              accordion = false;
              padding = 6.0;
              widget_spacing = 4;
            }
            {
              id = "sys";
              members = [
                "network"
                "3ri4ng0ld/ip-monitor:widget"
                "bluetooth"
                "volume"
                "brightness"
              ];
              accordion = false;
              padding = 6.0;
              widget_spacing = 4;
            }
            {
              id = "power";
              members = [
                "sysmon"
                "power_profile"
                "battery"
              ];
              accordion = false;
              padding = 6.0;
              widget_spacing = 4;
            }
            # Added 2026-09-25. Enabling a plugin does NOT put anything on
            # screen: every one of these ships its UI as a bar entry, and an
            # entry only renders when its `<plugin-id>:<entry-id>` string is
            # named in the layout. That is why the nine plugins enabled below
            # were invisible until this group existed.
            #
            # All of them went into ONE new capsule in `start` rather than into
            # `group:sys`: start is left-aligned and grows rightwards, while
            # `end` is right-aligned and clips its leftmost item on overflow
            # (how the notes widget once went missing). Keeping the new load out of `end`
            # leaves that failure mode where it was.
            #
            # The entry-id after the colon is each plugin's `[[widget]] id`,
            # not its name — `bar`, `widget` and `status` are common. To move
            # one, paste its string wherever it belongs:
            #
            #   ezequiel/mango_layouts:btn            layout switcher
            #   gambled23/mangowm-keymode:mangowm-keymode   shows resize keymode
            #   mindnbytes/nix-status:status          generations + flake inputs
            #   coder/deepseek_usage:bar              DeepSeek balance
            #
            # Deliberately NOT here:
            #   fel/ocr          its `grab` entry is a control-center tile, so
            #                    OCR is already reachable without bar space
            {
              id = "dev";
              members = [
                "ezequiel/mango_layouts:btn"
                "gambled23/mangowm-keymode:mangowm-keymode"
                "mindnbytes/nix-status:status"
                "coder/deepseek_usage:bar"
              ];
              accordion = false;
              padding = 6.0;
              widget_spacing = 4;
            }
          ];
        };

        widget."control-center" = {
          custom_image = distroLogo;
          custom_image_colorize = false;
        };
        # A plugin's bar widget takes its settings from the same `widget.<id>`
        # table as a builtin one, keyed by the full `<plugin-id>:<entry-id>`
        # spelling (config_export.cpp:367). NOT `plugin_settings.*` -- that
        # table is for keys a plugin declares as a top-level [[setting]], and
        # `inactive_color` is a [[widget.setting]], i.e. it belongs to the
        # widget entry. Putting it in plugin_settings parses, exports, and does
        # nothing; measured before this comment existed.
        widget."8bury/mini-docker:mini-docker" = {
          # widget.luau:46 fills the status dot with
          # `runningCount > 0 and active_color or inactive_color`, and
          # inactive_color defaults to "error" -- so a red dot sits in the bar
          # whenever no container is running, which on a laptop is nearly
          # always. Docker itself is fine (it is rootless here, so the unit to
          # ask about is `systemctl --user is-active docker`, which says
          # active); "nothing running" is not a fault. Same correction as
          # widget.sysmon below: red is for things that are wrong.
          inactive_color = "on_surface_variant";
          # The count is 0 unless something is actually running, and a widget
          # whose only state is "0" is a widget that says nothing. This hides
          # the glyph, the count and the dot entirely until a container comes
          # up, at which point it appears with a real number in it.
          status_mode = "running_only";
        };

        # "暂无播放内容" is not information. The widget sat there at full width
        # announcing that nothing was playing, which is most of the time.
        widget.media.hide_when_no_media = true;

        widget.network = {
          # The glyph already says connected / disconnected / which kind. The
          # SSID next to it is ~110 physical pixels of a string that does not
          # change and cannot be acted on; it is still one hover away.
          show_label = false;
        };

        widget.sysmon = {
          # `highlightColor` defaults to ColorRole::Error (sysmon_widget.h:58),
          # so the CPU gauge is drawn in the palette's *error* colour at every
          # load -- a permanent red tick next to "1%". Red should mean
          # something is wrong. Primary is the accent the rest of the bar uses.
          highlight_color = "primary";
          # The label is as wide as the number in it, so the widget grew and
          # shrank between "1%" and "100%" and shoved its neighbours sideways
          # several times a second. Pin it to the width of the widest value.
          label_min_width = 34;
        };

        widget.clock = {
          format = "{:%H:%M}";
          vertical_format = "{:%H\n%M}";
        };

        widget.workspaces = {
          # mango always defines all `tag_num` tags, so the bar would otherwise
          # show 1-9 permanently. This collapses a tag out of the row once it
          # holds no windows; the active tag stays visible even when empty.
          hide_when_empty = true;
        };

        wallpaper = {
          enabled = true;
          directory = wallpaperDir;
          fill_mode = "stretch";
          fill_color = "surface";
          transition_on_startup = true;
          transition = [
            "fade"
            "wipe"
            "disc"
            "stripes"
            "zoom"
            "honeycomb"
          ];
          transition_duration = 1200;
          default.path = defaultWallpaperPath;
          automation = {
            enabled = false;
            interval_seconds = 300;
            order = "random";
            recursive = true;
          };
        };

        backdrop = {
          enabled = true;
          blur_intensity = 0.55;
          tint_intensity = 0.65;
        };

        audio = {
          enable_overdrive = true;
          enable_sounds = true;
        };

        brightness = {
          enable_ddcutil = true;
          minimum_brightness = 0.05;
          monitor."eDP-1".backend = "backlight";
        };

        battery = {
          warning_threshold = 20;
        };

        # Screen corner triggers, on the bottom corners rather than the top
        # ones -- the bar sits at the top (margin_edge 6, margin_ends 8) and the
        # top corners are close enough to its hover area to fire by accident,
        # while the bottom edge is completely free now that the dock is off.
        # action only accepts none / launcher / control_center / window_switcher
        # / command (hotCornerActionSelect in settings_registry.cpp); note it is
        # a free-form string in the schema, so a typo passes validation and then
        # silently does nothing at runtime.
        hot_corners = {
          enabled = true;
          delay_ms = 200; # dwell time, so a cursor merely passing by does not fire it
          bottom_left.action = "launcher";
          bottom_right.action = "control_center";
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
          effects = true;
        };

        system.monitor = {
          enabled = true;
          gpu_poll_seconds = 0.0;
        };

        location = {
          auto_locate = true;
          address = "Jingkou Qu, China";
        };

        notification = {
          enable_daemon = true;
          layer = "overlay";
          background_opacity = 0.95;
        };

        osd = {
          position = "top_right";
          background_opacity = 0.95;
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

        lockscreen = {
          enabled = true;
          blur_intensity = 0.5;
          tint_intensity = 0.3;
          blurred_desktop = true;
        };
      };
    };
  };
}
