_: {
  # The chosen style is runtime state, not a rebuild: it is written to
  # stdpath("data") and re-applied on the next start. `<leader>fs` picks one
  # through fzf-lua (plugins/navigation/fzf.nix).
  extraConfigLua = ''
    local tokyonight = require("tokyonight")
    local style_file = vim.fn.stdpath("data") .. "/tokyonight-style"
    -- `day` is in the list deliberately: it is the one escape hatch for
    -- working outdoors, and the file it writes survives the session.
    local STYLES = { "night", "storm", "moon", "day" }

    local function apply_saved_style()
      local file = io.open(style_file, "r")
      if not file then return end
      local style = file:read("*line")
      file:close()
      if style and vim.tbl_contains(STYLES, style) then
        tokyonight.setup({ style = style })
        tokyonight.load()
      end
    end

    _G.select_tokyonight_style = function()
      local ok, fzf = pcall(require, "fzf-lua")
      if not ok then
        vim.notify("fzf-lua is required for style selection", vim.log.levels.WARN)
        return
      end
      fzf.fzf_exec(STYLES, {
        prompt = "Tokyo Night Style ❯ ",
        actions = {
          ["default"] = function(selected)
            if not selected or #selected == 0 then return end
            local new_style = selected[1]
            local file = io.open(style_file, "w")
            if file then
              file:write(new_style)
              file:close()
            else
              vim.notify("Failed to save style preference", vim.log.levels.ERROR)
              return
            end
            tokyonight.setup({ style = new_style })
            tokyonight.load()
            vim.notify(
              string.format("Applied '%s' style", new_style),
              vim.log.levels.INFO
            )
          end,
        },
      })
    end

    vim.schedule(apply_saved_style)
  '';
}
