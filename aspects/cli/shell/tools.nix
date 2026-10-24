{
  palette,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  colors = palette;

  batTheme = import ./onedark-darker-bat.nix {
    inherit pkgs;
    palette = colors;
  };

  glowStyle = (pkgs.formats.json { }).generate "onedark-darker-glow.json" {
    document = {
      block_prefix = "\n";
      block_suffix = "\n";
      color = colors.brightFg;
      margin = 1;
    };
    heading = {
      block_suffix = "\n";
      color = colors.blue;
      bold = true;
    };
    h1 = {
      prefix = " ";
      suffix = " ";
      color = colors.brightFg;
      background_color = colors.selection;
      bold = true;
    };
    h2.color = colors.purple;
    h2.bold = true;
    h3.color = colors.cyan;
    h4.color = colors.yellow;
    link = {
      color = colors.blue;
      underline = true;
    };
    link_text = {
      color = colors.cyan;
      bold = true;
    };
    image.color = colors.purple;
    code = {
      prefix = " ";
      suffix = " ";
      color = colors.orange;
      background_color = colors.surface;
    };
    code_block = {
      color = colors.brightFg;
      margin = 1;
      chroma = {
        text.color = colors.brightFg;
        comment.color = colors.fg;
        keyword.color = colors.cyan;
        keyword_reserved.color = colors.cyan;
        keyword_type.color = colors.yellow;
        operator.color = colors.cyan;
        punctuation.color = colors.fg;
        name.color = colors.brightFg;
        name_builtin.color = colors.cyan;
        name_tag.color = colors.brightFg;
        name_attribute.color = colors.blue;
        name_class.color = colors.yellow;
        name_decorator.color = colors.orange;
        name_function.color = colors.blue;
        literal_number.color = colors.orange;
        literal_string.color = colors.green;
        literal_string_escape.color = colors.cyan;
        generic_deleted = {
          color = colors.brightFg;
          background_color = batTheme.diff.delete;
        };
        generic_inserted = {
          color = colors.brightFg;
          background_color = batTheme.diff.add;
        };
      };
    };
    block_quote = {
      indent = 1;
      indent_token = "│ ";
    };
  };

in
{
  home = {
    packages = with pkgs; [
      ripgrep
      duf
      nix-output-monitor
      fd
      jq
      hexyl
      dust
      sops
      p7zip
      libqalculate
    ];

    # The same immutable, precompiled cache serves bat and delta. No activation
    # script writes a user cache; updates happen only when the Nix input changes.
    sessionVariables = lib.optionalAttrs (palette != null) {
      # CLI owns the selected theme; session support supplies only a fallback.
      BAT_THEME = batTheme.name;
      BAT_CACHE_PATH = "${batTheme.cache}";
    };

    activation.batCache = lib.mkIf (
      palette != null || (config.programs.bat.themes == { } && config.programs.bat.syntaxes == { })
      # force: The immutable precompiled Bat cache replaces HM activation-time cache generation.
    ) (lib.mkForce (lib.hm.dag.entryAnywhere ""));

  };
  programs = {
    bat = {
      enable = true;
      config = {
        theme = if palette == null then "base16" else batTheme.name;
        style = "numbers,changes,header";
      };
      themes = lib.optionalAttrs (palette != null) {
        ${batTheme.name}.src = pkgs.writeText "One Dark Darker.tmTheme" batTheme.tmTheme;
      };
    };

    delta.package = lib.mkIf (palette != null) batTheme.delta;

    eza = {
      enable = true;
      theme = lib.optionalAttrs (palette != null) {
        filekinds = {
          normal.foreground = colors.fg;
          directory = {
            foreground = colors.blue;
            is_bold = true;
          };
          symlink.foreground = colors.cyan;
          executable.foreground = colors.green;
          broken_symlink.foreground = colors.red;
        };
        git = {
          new.foreground = colors.green;
          modified.foreground = colors.yellow;
          deleted.foreground = colors.red;
          renamed.foreground = colors.cyan;
          ignored.foreground = colors.muted;
          conflicted.foreground = colors.red;
        };
        git_repo = {
          branch_main.foreground = colors.blue;
          branch_other.foreground = colors.purple;
          git_clean.foreground = colors.green;
          git_dirty.foreground = colors.yellow;
        };
        file_type = {
          image.foreground = colors.purple;
          video.foreground = colors.purple;
          music.foreground = colors.cyan;
          document.foreground = colors.blue;
          compressed.foreground = colors.orange;
          build = {
            foreground = colors.yellow;
            is_underline = true;
          };
        };
        size = {
          number_byte.foreground = colors.fg;
          number_kilo.foreground = colors.cyan;
          number_mega.foreground = colors.blue;
          number_giga.foreground = colors.purple;
          number_huge.foreground = colors.red;
        };
        date.foreground = colors.fg;
        inode.foreground = colors.fg;
        header.foreground = colors.cyan;
        punctuation.foreground = colors.border;
      };
    };

    tealdeer = {
      enable = true;
      enableAutoUpdates = false;
      settings.updates = {
        auto_update = true;
        auto_update_interval_hours = 168;
      };
    };

  };
  xdg.configFile = lib.optionalAttrs (palette != null) {
    "glow/onedark-darker.json".source = glowStyle;
    "glow/glow.yml".text = ''
      style: "${glowStyle}"
      pager: true
      mouse: true
    '';
  };
}
