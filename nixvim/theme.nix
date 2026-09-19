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

    -- Two traps, both measured on a headless build before this was written:
    --
    --  * `tokyonight.setup{ style = ... }` REPLACES the option table, it does
    --    not merge. Passing only `style` reverted `styles.floats` and
    --    `styles.sidebars` from "transparent" (set in
    --    plugins/appearance/colorscheme.nix) back to the plugin default
    --    "dark", so every float grew an opaque background.
    --  * `tokyonight.load()` does NOT fire Neovim's ColorScheme event. A
    --    tracer autocmd counted zero. highlights.nix hangs its whole override
    --    table off ColorScheme, so switching style silently threw away the
    --    transparent NormalFloat, the MultiCursor colours, TabLine, MatchParen
    --    and every link in that file -- with no error, for the rest of the
    --    session, and on every later start because the choice is persisted.
    --
    -- So: merge onto the live options, and go through `:colorscheme`, which
    -- does fire the event.
    local function set_style(style)
      local opts = vim.tbl_deep_extend(
        "force",
        require("tokyonight.config").options or {},
        { style = style }
      )
      tokyonight.setup(opts)
      vim.cmd.colorscheme("tokyonight")
    end

    local function apply_saved_style()
      local file = io.open(style_file, "r")
      if not file then return end
      local style = file:read("*line")
      file:close()
      if style and vim.tbl_contains(STYLES, style) then
        set_style(style)
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
            set_style(new_style)
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
