{
  pkgs,
  lib,
  config,
  ...
}:
let
  kittyDir = "${config.xdg.configHome}/kitty";
  noctaliaTheme = "${kittyDir}/themes/noctalia.conf";
  mainConf = "${kittyDir}/kitty.conf";

  # A store file rather than a heredoc in the activation script below: a
  # heredoc inside a Nix indented string loses its terminator's indentation and
  # silently produced an *empty* seed. apply.sh then created kitty.conf from
  # scratch with only its own include, so `include mayon.conf` was missing and
  # not one setting in this module applied -- invisible rather than fatal,
  # which is the worst kind.
  kittyStub = pkgs.writeText "kitty.conf" ''
    # Seeded by modules/home/programs/terminal/kitty.nix, then left alone.
    # Settings live in mayon.conf; the palette line is maintained by noctalia.
    include mayon.conf
    include themes/noctalia.conf
  '';
in
{
  # kitty replaced foot on 2026-09-19 for exactly one reason: the kitty
  # graphics protocol. snacks.nvim renders LaTeX as *typeset images* --
  # snacks/image/init.lua drives pdflatex over a `standalone` document and
  # pipes it through ImageMagick -- and snacks/image/terminal.lua only speaks
  # kitty, ghostty and wezterm. foot implements sixel and nothing else, which
  # is why nixvim/plugins/appearance/snacks.nix had `image.enabled = false`.
  # The alternative, utftex, draws maths as Unicode art; it is legible but it
  # is not typesetting, and this machine's notes are full of control-theory
  # formulae.
  #
  # foot was 96 MiB and this is not; that is the price. Reverting is one
  # commit -- nothing outside this file depended on the terminal beyond four
  # references (mango keybind and window rule, thunar's "open terminal",
  # noctalia's theme template).
  home.packages = [ pkgs.kitty ];

  # NOT `programs.kitty.settings`. That module owns kitty.conf and makes it a
  # read-only store symlink, which breaks noctalia's theme hook: its
  # assets/templates/kitty/apply.sh runs `touch "$config_file"` *before* it
  # checks anything, under `set -euo pipefail`. Measured: `touch` on a Home
  # Manager symlink returns "Permission denied", so the hook aborts on its
  # first line and the live `pkill -USR1 kitty` reload never runs.
  #
  # foot's template gets away with a read-only foot.ini because its apply.sh
  # greps first and never touches. kitty's does not, so ownership is split:
  # every real setting lives in this read-only file, and kitty.conf is a seeded
  # mutable stub that apply.sh is free to rewrite.
  xdg.configFile."kitty/mayon.conf".text = ''
    # Managed by modules/home/programs/terminal/kitty.nix -- edit there.

    font_family      JetBrainsMono Nerd Font
    font_size        11.0
    # Ligatures are most of the reason for this font; keep them everywhere
    # except under the cursor, so the character being edited stays identifiable.
    disable_ligatures cursor

    # Matches the alpha foot used. mango composites it (blur is on in
    # wm/mango/config.nix), so this is real translucency.
    background_opacity 0.8

    cursor_shape           beam
    cursor_beam_thickness  1.5
    cursor_blink_interval  0.5

    scrollback_lines            5000
    wheel_scroll_multiplier     5.0

    # mango draws the border and owns the layout; kitty's own chrome is noise.
    hide_window_decorations     yes
    window_padding_width        4
    confirm_os_window_close     0
    enable_audio_bell           no

    # `kitten ssh` ships kitty's terminfo to the remote host on connect, which
    # is what makes keeping the default TERM=xterm-kitty safe. foot set
    # TERM=xterm-256color for that same problem because it has no such kitten;
    # do not copy that setting across -- it would also cost the graphics
    # protocol that this whole migration is for.
    shell_integration           enabled

    # foot's bindings, kept so the muscle memory survives the swap.
    map ctrl+shift+o        open_url_with_hints
    map ctrl+u              scroll_page_up
    map ctrl+d              scroll_page_down
    map ctrl+shift+home     scroll_home
    map ctrl+shift+end      scroll_end
    map ctrl+equal          change_font_size all +1.0
    map ctrl+minus          change_font_size all -1.0
    map ctrl+0              change_font_size all 0
  '';

  # kitty.conf stays mutable and unmanaged, for the reason above: two includes
  # and nothing else. apply.sh preserves an existing `include
  # themes/noctalia.conf` exactly where it is ("Preserve the first existing
  # include", its awk program), so it finds the line, changes nothing, and
  # reloads.
  home.activation.seedKittyConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "${kittyDir}/themes"

    if [ ! -e "${noctaliaTheme}" ]; then
      run ${pkgs.coreutils}/bin/install -m 0644 /dev/null "${noctaliaTheme}"
    fi

    # A missing `include mayon.conf` loses every setting silently, so repair
    # that case too rather than only the file-absent one.
    if [ ! -e "${mainConf}" ] || ! ${pkgs.gnugrep}/bin/grep -q '^include mayon\.conf$' "${mainConf}"; then
      run ${pkgs.coreutils}/bin/install -m 0644 ${kittyStub} "${mainConf}"
    fi
  '';
}
