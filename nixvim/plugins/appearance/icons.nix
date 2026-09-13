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
  plugins.web-devicons = {
    enable = true;
    # File-type brand colours do not follow onedark's seven palettes.
    settings.color_icons = false;
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
