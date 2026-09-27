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

  # The `lg` alias in shell/zsh.nix points here. Use terminal ANSI colors so
  # the UI follows the active Noctalia palette.
  programs.lazygit = {
    enable = true;
    settings.gui = {
      border = "rounded";
      theme = {
        activeBorderColor = [
          "cyan"
          "bold"
        ];
        searchingActiveBorderColor = [
          "blue"
          "bold"
        ];
        inactiveBorderColor = [ "default" ];
        optionsTextColor = [ "cyan" ];
        # Reverse video adapts to both dark and light terminal palettes.
        selectedLineBgColor = [ "reverse" ];
        inactiveViewSelectedLineBgColor = [ "bold" ];
        cherryPickedCommitFgColor = [ "black" ];
        cherryPickedCommitBgColor = [ "cyan" ];
        markedBaseCommitFgColor = [ "black" ];
        markedBaseCommitBgColor = [ "yellow" ];
        unstagedChangesColor = [ "red" ];
        defaultFgColor = [ "default" ];
      };
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
      line-numbers-left-format = "{nm:>4} │";
      line-numbers-right-format = "{np:>4} │";
      line-numbers-left-style = "blue";
      line-numbers-right-style = "blue";
      line-numbers-zero-style = "brightblack";
      hunk-header-style = "file line-number syntax";
    };
  };
}
