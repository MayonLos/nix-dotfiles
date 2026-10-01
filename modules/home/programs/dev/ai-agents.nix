{
  pkgs,
  lib,
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

  # codex 0.157 split its app-server daemon out into a package it installs for
  # itself. Interactive startup now requires the directory above `bin/codex` to
  # look like a complete upstream CLI package — `codex-package.json`,
  # `codex-path/rg`, and a `codex-resources/bwrap` that is a real copy inside
  # the package root, because the installer rejects any link escaping it. The
  # llm-agents build ships the three binaries and nothing else, so bare `codex`
  # dies immediately with "this CLI has no complete local package"; the same
  # error names the workaround, `--no-daemon`, which is also what the pending
  # upstream fix (llm-agents.nix#9889) leaves as the non-daemon path.
  #
  # Completing the package here would be the other way out, and it is the wrong
  # one on NixOS. The daemon installs by copying the CLI out of the store into
  # ~/.codex/packages/app-server-daemon/releases, and because that root is not
  # named `standalone`, upstream's `is_stable_standalone_release` guard against
  # GNU/distro packages does not fire: the daemon would start its
  # `pid-update-loop` and quietly replace the Nix-provided binary with whatever
  # it downloads. `--no-daemon` keeps codex entirely under Nix and costs only
  # the shared-server features. `codex agents` is the one entry point that
  # rejects the flag — it *is* the daemon overview — so it is passed through
  # and still reports "no complete local package; the agents overview requires a
  # shared server". That subcommand is knowingly unavailable here, not broken.
  #
  # `--no-daemon` is a root-level clap flag, so it has to be inserted before the
  # subcommand. hiPrio wins the bin/codex collision with agents.codex in the
  # Home Manager buildEnv; the original wrapper is still what gets exec'd, so
  # codex's own helper lookup next to libexec/codex/bin is unchanged.
  codexCli = lib.hiPrio (
    pkgs.writeShellScriptBin "codex" ''
      for arg in "$@"; do
        case "$arg" in
          -*) continue ;;
          agents) exec ${agents.codex}/bin/codex "$@" ;;
          *) break ;;
        esac
      done
      exec ${agents.codex}/bin/codex --no-daemon "$@"
    ''
  );

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
    # DeepSeek's own agent harness ("everything is a plugin"), still 0.1.x.
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

    # OpenAI's CLI agent. Was ./codex until 2026-08-30: a symlinkJoin around
    # the sadjow/codex-cli-nix input, whose launcher injected ~10 `-c` overrides
    # to make bare `codex` mean DeepSeek. All of that is gone — bare `codex` is
    # now the ChatGPT account, which is the point. This source is also newer
    # than what it replaced (0.157.1 now; the sadjow input was 0.149.0, and
    # nixpkgs-unstable is on 0.156.1) and drops the `stdenv.isLinux`
    # deprecation-warning workaround that the old module carried, since it is
    # not built from upstream's package.nix.
    # ~/.codex/config.toml is still codex's own, unmanaged by Nix.
    #
    # codexCli shadows bin/codex with the --no-daemon shim explained above; the
    # package itself stays because the shim execs through its wrapper and the
    # rest of the CLI (libexec helpers, completions) comes from here.
    agents.codex
    codexCli

    # xAI's official Grok Build coding agent. Provides both `grok` for
    # interactive sessions and `agent` for automation. Authentication is via
    # browser OAuth on first launch or XAI_API_KEY for non-browser use.
    agents.grok

    # Terminal coding agent, provider-agnostic. OpenCode v2 (2.0.18), switched
    # from v1 (1.18.32) on 2026-09-28. Config path is unchanged
    # (~/.config/opencode/opencode.jsonc, currently just the schema stub).
    # Credentials move from ~/.local/share/opencode/auth.json into SQLite
    # (~/.local/share/opencode/opencode.db), migrated on first v2 run. v2 runs
    # through a shared background server and stores sessions in that database.
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
  #
  # It also carried a desktop-entry workaround that this file used to own:
  # ZCode rewrote ~/.local/share/applications/zcode.desktop on every launch,
  # pointing Exec at the raw Electron binary instead of the `bin/zcode` wrapper
  # (losing --enable-wayland-ime, so fcitx5 stopped working in it) and
  # hard-coding a store path that `nh clean` later turned into a dangling one.
  # That block went with it — if zcode ever returns, the workaround is in
  # `git log -- modules/home/programs/dev/ai-agents.nix`, not lost.
  #
  # Its local state (~/.zcode, 724 MB of workspace/checkpoints/logs plus
  # v2/credentials.json, and ~/.config/ZCode, 19 MB) was deleted by hand at the
  # same time; nothing in Nix manages those paths, so a rebuild does not
  # recreate them.
}
