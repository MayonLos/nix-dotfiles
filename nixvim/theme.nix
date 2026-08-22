{
  extraConfigLua = ''
    local onedark = require("onedark")
    local style_file = vim.fn.stdpath("data") .. "/onedark-style"
    local STYLES = { "dark", "darker", "cool", "deep", "warm", "warmer", "light" }

    local function apply_saved_style()
      local file = io.open(style_file, "r")
      if not file then return end
      local style = file:read("*line")
      file:close()
      if style and vim.tbl_contains(STYLES, style) then
        onedark.setup({ style = style })
        onedark.load()
      end
    end

    _G.select_onedark_style = function()
      local ok, fzf = pcall(require, "fzf-lua")
      if not ok then
        vim.notify("fzf-lua is required for style selection", vim.log.levels.WARN)
        return
      end
      fzf.fzf_exec(STYLES, {
        prompt = "OneDark Style ❯ ",
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
            onedark.setup({ style = new_style })
            onedark.load()
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
