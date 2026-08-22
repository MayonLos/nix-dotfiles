{
  pkgs,
  inputs,
  ...
}:

let
  # From sadjow/codex-cli-nix rather than nixpkgs: it tracks upstream's own
  # release binaries hourly, so it runs a couple of minor versions ahead of
  # nixpkgs-unstable. Same maintainer and same mechanism as the claude-code
  # input this config already uses.
  #
  # The `-c` overrides below pin config keys that codex owns; a fast-moving
  # version stream makes them likelier to drift. If codex starts rejecting them,
  # switching this one line back to `pkgs-unstable.codex` is the whole revert.
  codexPkg = inputs.codex-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # `codex` with no arguments should be DeepSeek, and codex has no config
  # key or env var for "use this profile by default", so the choice has to be
  # injected by a launcher.
  #
  # It is injected as `-c key=value` overrides rather than as
  # `--profile ds` (which layers $CODEX_HOME/ds.config.toml on top of
  # config.toml) because codex writes settings back into the *topmost* config
  # layer: project trust levels, [features], model-migration notices. Under
  # `--profile`, that target is the profile file, and a Nix-managed profile file
  # is a /nix/store symlink, so trusting a directory fails with
  #
  #   config/batchWrite failed: failed to persist config.toml:
  #   failed to persist config at /nix/store/…-hm_.codexds.config.toml
  #
  # `-c` overrides are not a layer, so the write target stays the mutable
  # ~/.codex/config.toml and both profiles share one project-trust list.
  #
  # model_catalog_json replaces the built-in model catalog rather than extending
  # it, which is why it must not reach the openai path — the launcher only ever
  # applies one override set per invocation.
  dsOverrides = [
    ''-c 'model="deepseek-v4-flash"' ''
    ''-c 'model_provider="deepseek"' ''
    ''-c 'model_reasoning_effort="high"' ''
    # Verbatim from https://cdn.deepseek.com/api-docs/codex-deepseek-setup-en.sh
    ''-c 'model_catalog_json="${./models.json}"' ''
    ''-c 'model_providers.deepseek.name="DeepSeek"' ''
    ''-c 'model_providers.deepseek.base_url="https://api.deepseek.com/"' ''
    ''-c 'model_providers.deepseek.wire_api="responses"' ''
    # The key comes from DEEPSEEK_API_KEY — exported from the sops secret by
    # modules/home/shell/zsh.nix — rather than the `experimental_bearer_token`
    # the DeepSeek docs suggest, so no plaintext token lands on disk. codex has
    # to be started from a shell that sourced it; the VS Code extension and the
    # ChatGPT desktop app will not see it.
    ''-c 'model_providers.deepseek.env_key="DEEPSEEK_API_KEY"' ''
    # codex_apps is the built-in ChatGPT-connector MCP endpoint
    # (chatgpt.com/backend-api/ps/mcp). It can't be reached from this network
    # and is unusable with the DeepSeek provider anyway; disabling it removes
    # the "MCP startup interrupted: codex_apps" warning on every launch.
    "-c 'features.apps=false' "
  ];

  # Escape hatch back to the ChatGPT account: `codex --profile gpt`. Only the
  # provider is pinned, so the model keeps following whatever config.toml says
  # — codex migrates that key itself (gpt-5.4 -> gpt-5.6-terra, and onwards).
  gptOverrides = [ ''-c 'model_provider="openai"' '' ];

  launcher = pkgs.writeShellScript "codex-launcher" ''
    real="${codexPkg}/bin/codex"

    ds=(${builtins.concatStringsSep " " dsOverrides})
    gpt=(${builtins.concatStringsSep " " gptOverrides})

    profile=ds
    args=()
    while [ $# -gt 0 ]; do
      case "$1" in
        -p | --profile) profile="$2"; shift 2 ;;
        --profile=*) profile="''${1#--profile=}"; shift ;;
        --) args+=("$@"); break ;;
        *) args+=("$1"); shift ;;
      esac
    done

    # Overrides have to precede any subcommand, hence the rebuilt argv.
    case "$profile" in
      ds) exec "$real" "''${ds[@]}" "''${args[@]}" ;;
      gpt) exec "$real" "''${gpt[@]}" "''${args[@]}" ;;
      # An unknown name is someone's own $CODEX_HOME/<name>.config.toml; pass it
      # through, but note it will hit the read-only-layer bug if Nix-managed.
      *) exec "$real" --profile "$profile" "''${args[@]}" ;;
    esac
  '';

  codex = pkgs.symlinkJoin {
    name = "codex-${codexPkg.version}-deepseek";
    paths = [ codexPkg ];
    postBuild = ''
      rm "$out/bin/codex"
      install -m555 ${launcher} "$out/bin/codex"
    '';
  };
in
{
  # No .codex/*.config.toml here on purpose — see the launcher comment. Nothing
  # under ~/.codex is Nix-managed; codex owns config.toml outright.
  #
  # deepseek-v4-pro is in models.json but the API still refuses it over the
  # Responses wire ("Codex integration with deepseek-v4-pro will be available
  # starting early August 2026"), so dsOverrides pins flash.
  home.packages = [ codex ];
}
