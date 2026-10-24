{
  palette ? null,
}:
{ config, lib, ... }:
let
  mix =
    base: tint: percent:
    import ./color-mix.nix { inherit base tint percent; };
  diff =
    if palette == null then
      null
    else
      {
        add = mix palette.deep palette.green 8;
        addEmph = mix palette.deep palette.green 12;
        delete = mix palette.deep palette.red 8;
        deleteEmph = mix palette.deep palette.red 12;
        change = mix palette.deep palette.blue 8;
        changeEmph = mix palette.deep palette.blue 12;
      };
in
{
  programs = {
    git = {
      enable = true;
      settings = {
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
    gh = {
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

    # The `lg` alias in zsh.nix points here. Standalone consumers use ANSI;
    # a selected appearance supplies a quiet selection surface instead of
    # reversing the entire row's foreground and background.
    lazygit = {
      enable = true;
      settings.gui = {
        border = "rounded";
        theme = {
          activeBorderColor = [
            "cyan"
          ];
          searchingActiveBorderColor = [
            "blue"
          ];
          inactiveBorderColor = [ "default" ];
          optionsTextColor = [ "cyan" ];
          selectedLineBgColor = [ "reverse" ];
          inactiveViewSelectedLineBgColor = [ "reverse" ];
          cherryPickedCommitFgColor = [ "black" ];
          cherryPickedCommitBgColor = [ "cyan" ];
          markedBaseCommitFgColor = [ "black" ];
          markedBaseCommitBgColor = [ "yellow" ];
          unstagedChangesColor = [ "red" ];
          defaultFgColor = [ "default" ];
        }
        // (
          if palette == null then
            { }
          else
            {
              activeBorderColor = [ palette.blue ];
              searchingActiveBorderColor = [ palette.cyan ];
              inactiveBorderColor = [ palette.surface ];
              optionsTextColor = [ palette.cyan ];
              selectedLineBgColor = [ palette.selection ];
              inactiveViewSelectedLineBgColor = [ palette.selection ];
              cherryPickedCommitFgColor = [ palette.black ];
              cherryPickedCommitBgColor = [ palette.cyan ];
              markedBaseCommitFgColor = [ palette.black ];
              markedBaseCommitBgColor = [ palette.yellow ];
              unstagedChangesColor = [ palette.red ];
              defaultFgColor = [ palette.brightFg ];
            }
        );
      };
      # LazyGit 0.61 uses the native pagers array. Reuse the same immutable
      # cache wrapper and Git settings as command-line diff review.
      settings.git.pagers = lib.optionals (palette != null) [
        {
          colorArg = "always";
          pager = "${lib.getExe config.programs.delta.package} --paging=never";
        }
      ];
    };

    delta = {
      enable = true;
      # Without this, `delta` is merely installed: the module writes
      # pager.diff / interactive.diffFilter / pager.blame into git's config only
      # when enableGitIntegration is set, and it defaults to false. `git diff`
      # rendered through git's own pager until this line existed.
      enableGitIntegration = true;
      options = {
        # tools.nix supplies Delta's wrapper for the same build-time Bat cache.
        syntax-theme = if palette == null then "base16" else "One Dark";
        navigate = true;
        side-by-side = true;
        line-numbers = true;
        line-numbers-left-format = "{nm:>4} │";
        line-numbers-right-format = "{np:>4} │";
        line-numbers-left-style = if palette == null then "blue" else palette.blue;
        line-numbers-right-style = if palette == null then "blue" else palette.blue;
        line-numbers-zero-style = if palette == null then "brightblack" else palette.fg;
        hunk-header-style = "file line-number syntax";
      }
      // (
        if diff == null then
          { }
        else
          {
            plus-style = "${palette.brightFg} ${diff.add}";
            plus-emph-style = "${palette.brightFg} ${diff.addEmph}";
            minus-style = "${palette.brightFg} ${diff.delete}";
            minus-emph-style = "${palette.brightFg} ${diff.deleteEmph}";
            "line-numbers-plus-style" = "${palette.green}";
            "line-numbers-minus-style" = "${palette.red}";
            "line-numbers-zero-style" = "${palette.fg}";
          }
      );
    };
  };

}
