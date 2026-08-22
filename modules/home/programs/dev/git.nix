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

  programs.delta = {
    enable = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = true;
    };
  };
}
