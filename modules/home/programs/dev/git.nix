_: {
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "MayonLos";
        email = "ml20061023@outlook.com";
      };
      alias = {
        lg = "log --oneline --graph --decorate --all";
        st = "status -s";
        co = "checkout";
        undo = "reset --soft HEAD~1";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
      merge.conflictstyle = "diff3";
    };
  };

  # The GitHub CLI. `programs.gh` writes ~/.config/gh/config.yml only — the
  # token lives in hosts.yml, which Home Manager does not touch, so enabling
  # this does not disturb an existing login.
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
      aliases = {
        pv = "pr view --web";
        rv = "repo view --web";
      };
    };
  };

  # The `lg` alias in shell/zsh.nix points here. Its colours are hex for the
  # same reason fastfetch's are (apps/sysinfo.nix): lazygit paints its own
  # panels rather than reading the terminal palette, so it cannot follow a
  # noctalia theme change and is pinned to Tokyo Night by hand instead.
  programs.lazygit = {
    enable = true;
    settings.gui.theme = {
      activeBorderColor = [
        "#7aa2f7"
        "bold"
      ];
      searchingActiveBorderColor = [
        "#7dcfff"
        "bold"
      ];
      inactiveBorderColor = [ "#414868" ];
      optionsTextColor = [ "#7aa2f7" ];
      selectedLineBgColor = [ "#292e42" ];
      inactiveViewSelectedLineBgColor = [ "#283457" ];
      cherryPickedCommitFgColor = [ "#1a1b26" ];
      cherryPickedCommitBgColor = [ "#7dcfff" ];
      markedBaseCommitFgColor = [ "#1a1b26" ];
      markedBaseCommitBgColor = [ "#e0af68" ];
      unstagedChangesColor = [ "#f7768e" ];
      defaultFgColor = [ "#c0caf5" ];
    };
  };

  programs.delta = {
    enable = true;
    # Without this, `delta` is merely installed: the module writes
    # pager.diff / interactive.diffFilter / pager.blame into git's config only
    # when enableGitIntegration is set, and it defaults to false. `git diff`
    # rendered through git's own pager until this line existed.
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = true;
    };
  };
}
