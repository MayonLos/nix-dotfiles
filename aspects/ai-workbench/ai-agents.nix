{
  pkgs,
  inputs,
  ...
}:

# AI coding agents that come from the llm-agents.nix flake input rather than
# nixpkgs. The base packages are prebuilt on cache.numtide.com (configured in
# aspects/system/maintenance/nix.nix); the local compatibility fix and desktop launcher
# below reuse those packages.
let
  agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # dsh's app-boot loads `node-addon-require-builtin`, a native addon that
  # decodes the machine code of a V8-internal getter to find
  # `PrincipalRealm::builtin_module_require()`. nixpkgs' cc-wrapper compiles
  # every x86_64/aarch64 package with leaf frame pointers
  # (-fno-omit-frame-pointer -mno-omit-leaf-frame-pointer), which wraps that
  # getter in a prologue/epilogue the decoder does not recognize, so boot aborts
  # with "x64 sysv getter is not a recognized this->field accessor
  # (wide-window retry: ...)". It is a build-flag mismatch, not a dsh bug:
  # official nodejs.org binaries work. Root cause and discussion live in
  # NixOS/nixpkgs#565667; llm-agents.nix#9994 carries the stub below.
  #
  # Stub the addon out instead of rebuilding Node with frame pointers disabled.
  # `addon.requireBuiltin(id)` becomes `require(id)`, which returns the same
  # internal modules because the wrapper already runs Node with
  # --expose-internals. This is the upstream-reported workaround; the cost is
  # that dsh's plugin-package interception goes through Node's normal resolver
  # rather than the addon's routing. Remove once dsh (or the addon, or nixpkgs'
  # Node) handles frame-pointer builds.
  dshCli = agents.dsh.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      substituteInPlace \
        $out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-app-boot/lib/index.js \
        --replace-fail \
        'createRequire(import.meta.url)("node-addon-require-builtin")' \
        '{ requireBuiltin: createRequire(import.meta.url) }'
    '';
  });

  dshDesktop = pkgs.callPackage ./dsh-desktop.nix { dsh = dshCli; };

  # Use the desktop's Harness home by default instead of reactivating legacy
  # ~/.dsh plugins. Explicit DSH_HOME still supports isolated scripts and CI.
  dshCommand = pkgs.writeShellScriptBin "dsh" ''
    dsh_home="''${DSH_HOME:-}"
    if [[ "$dsh_home" =~ ^[[:space:]]*$ ]]; then
      dsh_home="''${XDG_DATA_HOME:-$HOME/.local/share}/dsh-desktop/harness"
    fi
    export DSH_HOME="$dsh_home"
    exec ${pkgs.lib.getExe dshCli} "$@"
  '';

in
{
  home.packages = [
    # Upstream has no Linux Electron release yet. Keep its official Web UI in
    # a dedicated desktop window; the command uses the same patched runtime.
    # Runtime state lives in $XDG_DATA_HOME/dsh-desktop/harness (defaulting to
    # ~/.local/share), isolated from the removed CLI's ~/.dsh plugins.
    dshDesktop
    dshCommand

    # OpenAI's CLI agent, authenticated through the user's ChatGPT account.
    # Its ~/.codex/config.toml remains user-managed, outside Nix.
    #
    # llm-agents provides the complete package layout and a daemon patch using
    # the immutable store package. Verified with an isolated 0.162.1 cold start;
    # the former --no-daemon wrapper is no longer needed.
    agents.codex

    # Claude Code's Nix-managed CLI; authentication and history stay user-owned.
    agents.claude-code

    # xAI's official Grok Build coding agent. Provides both `grok` for
    # interactive sessions and `agent` for automation. Authentication is via
    # browser OAuth on first launch or XAI_API_KEY for non-browser use.
    agents.grok
  ];

  # NOT here: `agents.zcode` (Z.ai's Electron IDE). Removed 2026-09-19 at the
  # user's instruction after it was observed pushing to a user repository
  # without being asked. Do not add it back.
}
