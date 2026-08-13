{ pkgs, pkgs-unstable, ... }:

let
  # `codex` with no arguments should be DeepSeek. Codex 0.146 offers exactly one
  # layering mechanism — `--profile NAME` reads $CODEX_HOME/NAME.config.toml on
  # top of config.toml — and no config key or env var for "use this profile by
  # default". config.toml itself cannot be Nix-managed, because codex rewrites
  # it (project trust levels, [features], model-migration notices), so the flag
  # has to be injected here instead.
  #
  # Injecting unconditionally would break `codex --profile gpt`: clap rejects a
  # repeated --profile outright ("cannot be used multiple times"), so the
  # launcher steps aside as soon as the caller names a profile themselves.
  launcher = pkgs.writeShellScript "codex-launcher" ''
    real="${pkgs-unstable.codex}/bin/codex"

    for arg in "$@"; do
      case "$arg" in
        --) break ;;
        -p | --profile | --profile=*) exec "$real" "$@" ;;
      esac
    done

    exec "$real" --profile ds "$@"
  '';

  codex = pkgs.symlinkJoin {
    name = "codex-${pkgs-unstable.codex.version}-deepseek";
    paths = [ pkgs-unstable.codex ];
    postBuild = ''
      rm "$out/bin/codex"
      install -m555 ${launcher} "$out/bin/codex"
    '';
  };
in
{
  home.packages = [ codex ];

  # The key comes from DEEPSEEK_API_KEY — exported from the sops secret by
  # modules/home/shell/zsh.nix — rather than the `experimental_bearer_token`
  # the DeepSeek docs suggest, so no plaintext token lands on disk. codex has to
  # be started from a shell that sourced it; the VS Code extension and the
  # ChatGPT desktop app will not see it.
  #
  # model_catalog_json belongs inside the profile and not at top level, where
  # DeepSeek's own setup script puts it: it replaces the built-in model catalog
  # rather than extending it, which leaves the OpenAI models reporting
  # "Model metadata for `gpt-5.4` not found. Defaulting to fallback metadata".
  #
  # deepseek-v4-pro is in models.json but the API still refuses it over the
  # Responses wire ("Codex integration with deepseek-v4-pro will be available
  # starting early August 2026"), so this pins flash.
  home.file = {
    ".codex/ds.config.toml".text = ''
      model = "deepseek-v4-flash"
      model_provider = "deepseek"
      model_reasoning_effort = "high"
      # Verbatim from https://cdn.deepseek.com/api-docs/codex-deepseek-setup-en.sh
      model_catalog_json = "${./models.json}"

      [model_providers.deepseek]
      name = "DeepSeek"
      base_url = "https://api.deepseek.com/"
      wire_api = "responses"
      env_key = "DEEPSEEK_API_KEY"

      # codex_apps is the built-in ChatGPT-connector MCP endpoint
      # (chatgpt.com/backend-api/ps/mcp). It can't be reached from this
      # network and is unusable with the DeepSeek provider anyway; disabling
      # it removes the "MCP startup interrupted: codex_apps" warning on every
      # launch.
      [features]
      apps = false
    '';

    # Escape hatch back to the ChatGPT account: `codex --profile gpt`. Only the
    # provider is pinned, so the model keeps following whatever config.toml says
    # — codex migrates that key itself (gpt-5.4 -> gpt-5.6-terra, and onwards).
    ".codex/gpt.config.toml".text = ''
      model_provider = "openai"

      # If chatgpt.com is unreachable from this network, add the same block as
      # in ds.config.toml to suppress the codex_apps startup warning here too:
      #   [features]
      #   apps = false
    '';
  };
}
