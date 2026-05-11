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

  programs.delta = {
    enable = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = true;
    };
  };
}
