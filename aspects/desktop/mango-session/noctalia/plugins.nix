{ inputs }: {
  # Immutable plugin sources are pinned by flake.lock and available
  # offline. Git sources fetch during startup; update them through Nix.
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
        # The pinned community-plugins now guards both of quill's
        # nextDueInMs() return paths, so the former local patch for its
        # index-service crash is gone.
        location = "${inputs.noctalia-plugins-community}";
        enabled = true;
      }
    ];

    # The pre-start ownership handoff removes only declared public
    # override paths, backing up those values before starting the writer.
    # Avoid compositor editor plugins that write the read-only HM config
    # and plugins whose external tools only support Hyprland.
    enabled = [
      "3ri4ng0ld/ip-monitor"
      "8bury/mini-docker"
      "cleboost/jetbrains-provider"
      "dunarand/tmux-provider"
      "noctalia/bongocat"
      "noctalia/translator"
      "radimous/prismlauncher-instances"
      "rxtsel/portctl"
      "ezequiel/mango_layouts" # jq + mmsg
      # Markdown notes, todos and /nt launcher entry; AI calls Go directly.
      "fel/quill"
      "gambled23/mangowm-keymode" # mmsg; shows the keymode SUPER,R enters

      # Notes/todo plugins were consolidated into Quill. OCR is provided
      # by the native Print bindings; its plugin had no configured entry.
      # The unused DeepSeek balance widget is disabled; its GUI data is
      # left in the runtime state, outside this store configuration.
    ];
  };

  # Plugin-level [[setting]] values belong here; [[widget.setting]]
  # values belong in widget."<plugin-id>:<entry-id>". Keep secrets in
  # runtime state or supported runtime files, never in Nix strings.
  plugin_settings = {
    # Explicit /tr queries use the selected online provider; ordinary launcher
    # searches never go through the translation service.
    "noctalia/translator" = {
      provider = "google";
      target_lang = "zh-CN";
    };
    # Noctalia injects generic panel settings for non-persistent entries.
    "ezequiel/mango_layouts" = {
      panel_placement = "attached";
      panel_position = "auto";
      panel_open_near_click = true;
    };
    # Call Go directly without the removed CLI. Use its raw model ID;
    # the locked plugin still defaults to the older Zen endpoint/model.
    "fel/quill" = {
      ai_backend = "opencode-go";
      ai_model = "deepseek-v4.1-flash";
      ai_base_url = "https://opencode.ai/inference/go/openai/v1";
    };

  };
}
