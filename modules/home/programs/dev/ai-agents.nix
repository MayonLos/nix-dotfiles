{
  pkgs,
  inputs,
  ...
}:

# AI coding agents that come from the llm-agents.nix flake input rather than
# nixpkgs. Everything here is prebuilt on cache.numtide.com (the substituter is
# added in modules/system/core/nix.nix), so none of it compiles locally.
#
# github-copilot-cli stays in ../../packages.nix — its source tracks upstream
# closely.
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

  # llm-agents.nix ships OpenCode v2's binary as `opencode2` (upstream's real
  # name is `opencode`; the suffix avoids colliding with the v1 package). The
  # fel/quill noctalia plugin drives the literal name `opencode` and its backend
  # is not configurable, and codecompanion hardcodes `opencode` too, so expose
  # v2 under `opencode` with a thin wrapper. `opencode2` is still installed for
  # calling the v2 entry point explicitly.
  opencodeCli = pkgs.writeShellScriptBin "opencode" ''
    exec ${agents.opencode2}/bin/opencode2 "$@"
  '';
in
{
  home.packages = [
    # DeepSeek's own agent harness ("everything is a plugin").
    # `dsh` alone is an error: it needs a profile, and only two ship —
    # `dsh web` (the browser UI, the one you actually want) and
    # `dsh --profile headless "<task>"` for one-shot answers. The `tui` and
    # `code` profiles in upstream's --help examples do NOT exist here; they are
    # out-of-tree plugin bundles you would have to add yourself. Profiles and
    # plugins live in $DSH_HOME and are installed at runtime by `dsh plugin add`,
    # which shells out to pnpm — mutable state outside the store, needing
    # corepack/pnpm on PATH (nodejs in ../../packages.nix provides corepack).
    # Credentials are configured on first run, not read from DEEPSEEK_API_KEY.
    # dshCli, not agents.dsh directly, because of the loader stub above.
    dshCli

    # OpenAI's CLI agent, authenticated through the user's ChatGPT account.
    # Its ~/.codex/config.toml remains user-managed, outside Nix.
    #
    # llm-agents provides the complete package layout and a daemon patch using
    # the immutable store package. Verified with an isolated 0.162.1 cold start;
    # the former --no-daemon wrapper is no longer needed.
    agents.codex

    # xAI's official Grok Build coding agent. Provides both `grok` for
    # interactive sessions and `agent` for automation. Authentication is via
    # browser OAuth on first launch or XAI_API_KEY for non-browser use.
    agents.grok

    # Terminal coding agent with provider support. The locked llm-agents input
    # exposes v2 as `opencode2`; the wrapper above also provides `opencode`.
    # Configuration and credentials remain mutable runtime state outside Nix.
    agents.opencode2
    opencodeCli

    # Token usage and cost across the agent CLIs, read from their local session
    # files — nothing is uploaded. Covers codex and the other installed agents.
    agents.ccusage

    # Local-first review of agent output: plans, diffs, web pages. Useful with
    # the agents producing changes here.
    agents.crit

    # MCP runtime and CLI — for driving and debugging MCP servers from the
    # shell. nvim already talks to them through mcphub (see
    # nixvim/plugins/ai/mcphub.nix and the mcp-hub flake input).
    agents.mcporter

    # Filesystem and network restrictions for agent processes. The binary is
    # `srt`, not `sandbox-runtime`. The lightweight option; `nono` in the same
    # flake is the kernel-enforced one, deliberately not installed here.
    agents.sandbox-runtime

    # git worktree per branch, tmux window per worktree — for running several
    # agents in parallel. Pairs with ../terminal/tmux.nix.
    agents.workmux
  ];

  # NOT here: `agents.zcode` (Z.ai's Electron IDE). Removed 2026-09-19 at the
  # user's instruction after it was observed pushing to a user repository
  # without being asked. Do not add it back.
}
