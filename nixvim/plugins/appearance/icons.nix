{ lib, ... }:
let
  # Navic, completion and Trouble describe the same LSP kinds; a single table
  # keeps their glyphs identical without depending on plugin load order.
  kinds = {
    File = "";
    Module = "";
    Namespace = "";
    Package = "";
    Class = "";
    Method = "";
    Property = "";
    Field = "";
    Constructor = "";
    Enum = "";
    Interface = "";
    Function = "";
    Variable = "";
    Constant = "";
    String = "";
    Number = "";
    Boolean = "";
    Array = "";
    Object = "";
    Key = "";
    Null = "";
    EnumMember = "";
    Struct = "";
    Event = "";
    Operator = "";
    TypeParameter = "";
  };
  paddedKinds = lib.mapAttrs (_: icon: icon + " ") kinds;
  severity = {
    error = "󰅚";
    warn = "󰀪";
    info = "󰋽";
    hint = "󰌶";
  };
in
{
  # Brand colours on purpose: they are the fastest way to tell one file from
  # another in the tabline and in fzf-lua's list, and that beats matching
  # the colorscheme's palette. Nothing else here relinks the DevIcon* groups.
  plugins.web-devicons.enable = true;

  # devicons keys .m to ObjectiveC, and its glyph is near enough to C's that a
  # MATLAB file reads as a C file in the tabline and the explorer. There is no
  # matlab entry at all -- get_icon_by_filetype("matlab") returns nil -- so this
  # adds one rather than correcting one.
  #
  # Objective-C loses the extension. That is the intended trade here: nothing on
  # this host writes Objective-C, and Neovim resolves every .m tested to the
  # matlab filetype anyway. clangd's objc entry in lsp/servers.nix is the
  # upstream default, not evidence to the contrary.
  #
  # U+F0628 nf-md-matrix, because MATLAB is "matrix laboratory" and it is
  # visually nothing like C's glyph. Checked against the actual font rather than
  # assumed: it is in JetBrainsMonoNerdFont-Regular's cmap, as are the rest.
  # The colour is MATLAB's brand orange, per the brand-colours note above.
  plugins.web-devicons.settings.override =
    let
      matlab = {
        icon = "󰘨";
        color = "#e16737";
        cterm_color = "173";
        name = "Matlab";
      };
    in
    {
      m = matlab;
      mlx = matlab // {
        name = "MatlabLiveScript";
      };
      mat = matlab // {
        name = "MatlabData";
      };
      slx = matlab // {
        name = "Simulink";
      };
    };
  plugins.navic.settings.icons = paddedKinds;
  plugins.blink-cmp.settings.appearance.kind_icons = kinds;
  plugins.trouble.settings.icons.kinds = paddedKinds;
  plugins.snacks.settings.notifier.icons = {
    inherit (severity) error warn info;
    debug = "";
    trace = "";
  };
  diagnostic.settings.signs.text.__raw = ''
    {
      [vim.diagnostic.severity.ERROR] = "${severity.error} ",
      [vim.diagnostic.severity.WARN] = "${severity.warn} ",
      [vim.diagnostic.severity.INFO] = "${severity.info} ",
      [vim.diagnostic.severity.HINT] = "${severity.hint} ",
    }
  '';
}
