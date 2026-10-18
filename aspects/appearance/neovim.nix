{ palette }:
{ lib, ... }:
lib.optionalAttrs (palette != null) {
  # A minimal adapter proof; the rich Lua theme will be migrated separately.
  programs.neovim.initLua = ''
    do
      local c = ${lib.generators.toLua { } palette}
      vim.o.background = "dark"
      vim.g.colors_name = c.name
      vim.api.nvim_set_hl(0, "Normal", { fg = c.fg, bg = c.bg })
      vim.api.nvim_set_hl(0, "NormalFloat", { fg = c.fg, bg = c.deep })
      vim.api.nvim_set_hl(0, "FloatBorder", { fg = c.border, bg = c.deep })
      vim.api.nvim_set_hl(0, "Visual", { bg = c.selection })
      local ansi = ${lib.generators.toLua { } (import ./ansi.nix palette)}
      for i, color in ipairs(ansi) do vim.g["terminal_color_" .. (i - 1)] = color end
    end
  '';
}
