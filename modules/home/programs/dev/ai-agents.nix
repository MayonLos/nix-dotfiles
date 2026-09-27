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
    agents.dsh

    # OpenAI's CLI agent. Was ./codex until 2026-08-30: a symlinkJoin around
    # the sadjow/codex-cli-nix input, whose launcher injected ~10 `-c` overrides
    # to make bare `codex` mean DeepSeek. All of that is gone — bare `codex` is
    # now the ChatGPT account, which is the point. This source is also newer
    # than what it replaced (0.150.1 vs 0.149.0; nixpkgs-unstable is on 0.147.0)
    # and drops the `stdenv.isLinux` deprecation-warning workaround that the old
    # module carried, since it is not built from upstream's package.nix.
    # ~/.codex/config.toml is still codex's own, unmanaged by Nix.
    #
    # codexCli shadows bin/codex with the --no-daemon shim explained above; the
    # package itself stays because the shim execs through its wrapper and the
    # rest of the CLI (libexec helpers, completions) comes from here.
    agents.codex
    codexCli

    # The ChatGPT/Codex desktop app. Wrapped with --ozone-platform=wayland when
    # NIXOS_OZONE_WL is set. Note it authenticates on its own and will not see
    # the shell environment, so nothing here depends on sops.
    agents.chatgpt

    # xAI's official Grok Build coding agent. Provides both `grok` for
    # interactive sessions and `agent` for automation. Authentication is via
    # browser OAuth on first launch or XAI_API_KEY for non-browser use.
    agents.grok

    # Terminal coding agent, provider-agnostic. Config lives in
    # ~/.config/opencode/opencode.json. Ahead of nixpkgs (1.18.25 vs 1.18.18 on
    # nixos-unstable, 1.15.10 on stable).
    agents.opencode

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
