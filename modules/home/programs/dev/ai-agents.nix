{
  pkgs,
  inputs,
  ...
}:

# AI coding agents that come from the llm-agents.nix flake input rather than
# nixpkgs. Everything here is prebuilt on cache.numtide.com (the substituter is
# added in modules/system/core/nix.nix), so none of it compiles locally.
#
# claude-code and github-copilot-cli stay in ../../packages.nix, and codex stays
# in ./codex — those already have working sources that track upstream closely.
let
  agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
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

    # Terminal coding agent, provider-agnostic. Config lives in
    # ~/.config/opencode/opencode.json. Ahead of nixpkgs (1.18.25 vs 1.18.18 on
    # nixos-unstable, 1.15.10 on stable).
    agents.opencode

    # Z.ai's Electron desktop IDE. Not in nixpkgs at all — upstream ships only
    # .deb/.rpm/AppImage; this package unpacks the .deb and patches the RUNPATH.
    # Its bin/zcode wrapper adds the Chromium Wayland flags (including
    # --enable-wayland-ime, which fcitx5 needs) and puts xdg-utils on PATH.
    # See xdg.desktopEntries.zcode below for why that wrapper needs defending.
    agents.zcode

    # Token usage and cost across the agent CLIs, read from their local session
    # files — nothing is uploaded. Covers claude-code and codex, both of which
    # are already installed.
    agents.ccusage

    # Local-first review of agent output: plans, diffs, web pages. Useful with
    # three agents (claude-code, codex, copilot-cli) producing changes here.
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

  # ZCode rewrites ~/.local/share/applications/zcode.desktop on every launch,
  # pointing Exec at lib/ZCode/zcode — the *raw* Electron binary, not the
  # bin/zcode wrapper. Since ~/.local/share outranks /etc/profiles in
  # XDG_DATA_DIRS, that self-written entry wins for both the app launcher and
  # the zcode:// OAuth callback, so ZCode ends up started without
  # --enable-wayland-ime (no fcitx5 input) and without xdg-utils on PATH. It
  # also hard-codes a store path, which `nh clean` turns into a dangling one
  # after an update.
  #
  # Owning the file here restores the correct entry on every activation. It
  # does NOT make the rewrite fail: ZCode unlinks the store symlink and writes
  # a fresh 0600 regular file (it owns the directory, so read-only targets stop
  # nothing) — the entry is only guaranteed correct between an activation and
  # the next ZCode launch. `force` is what keeps that from breaking boot: with
  # home-manager.backupFileExtension = "backup" (flake/system.nix) the second
  # activation after a rewrite found a leftover zcode.desktop.backup in the way
  # and failed checkLinkTargets, taking home-manager-mayon.service down at
  # startup. force overwrites in place and never backs up.
  #
  # Keep the fields in sync with the package's own desktop item
  # (share/applications/zcode.desktop).
  # xdg.enable is false on this host, so xdg.desktopEntries emits nothing —
  # write the file directly instead.
  home.file.".local/share/applications/zcode.desktop" = {
    force = true;
    source =
      (pkgs.makeDesktopItem {
        name = "zcode";
        desktopName = "ZCode";
        genericName = "Agentic Development Environment";
        comment = "ZCode Desktop App";
        exec = "zcode %U";
        icon = "zcode";
        terminal = false;
        categories = [ "Development" ];
        mimeTypes = [ "x-scheme-handler/zcode" ];
        startupWMClass = "ZCode";
      })
      + "/share/applications/zcode.desktop";
  };
}
