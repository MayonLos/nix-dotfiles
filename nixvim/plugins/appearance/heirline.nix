{ pkgs, ... }:
{
  extraPlugins = [ pkgs.vimPlugins.heirline-nvim ];

  extraConfigLua = ''
    local heirline   = require("heirline")
    local conditions = require("heirline.conditions")
    local utils      = require("heirline.utils")

    local function setup_colors()
      return {
        bg         = utils.get_highlight("StatusLine").bg,
        fg         = utils.get_highlight("StatusLine").fg,
        bright_bg  = utils.get_highlight("Folded").bg,
        gray       = utils.get_highlight("NonText").fg,
        blue       = utils.get_highlight("Function").fg,
        green      = utils.get_highlight("String").fg,
        purple     = utils.get_highlight("Statement").fg,
        orange     = utils.get_highlight("Constant").fg,
        red        = utils.get_highlight("DiagnosticError").fg,
        cyan       = utils.get_highlight("Special").fg,
        git_add    = utils.get_highlight("Added").fg    or utils.get_highlight("diffAdded").fg,
        git_change = utils.get_highlight("Changed").fg  or utils.get_highlight("diffChanged").fg,
        git_del    = utils.get_highlight("Removed").fg  or utils.get_highlight("diffRemoved").fg,
      }
    end

    local Space = { provider = " " }
    local Align = { provider = "%=" }

    local function pill(color, inner)
      local function resolve(self) return type(color) == "function" and color(self) or color end
      local function cap(self) return { fg = resolve(self), bg = "bg" } end
      inner.hl = function(self) return { fg = "bg", bg = resolve(self), bold = true } end
      return {
        { provider = "", hl = cap },
        inner,
        { provider = "", hl = cap },
      }
    end

    local mode_colors = {
      n = "blue",  i = "green",  v = "purple", V = "purple", ["\22"] = "purple",
      c = "orange", s = "purple", S = "purple", ["\19"] = "purple",
      R = "red",   r = "red",    ["!"] = "red", t = "green",
    }
    local mode_names = {
      n = "NORMAL", niI = "NORMAL", niR = "NORMAL", niV = "NORMAL",
      no = "O-PENDING", nov = "O-PENDING", noV = "O-PENDING",
      i = "INSERT", ic = "INSERT", ix = "INSERT",
      v = "VISUAL", V = "V-LINE", ["\22"] = "V-BLOCK",
      s = "SELECT", S = "S-LINE", ["\19"] = "S-BLOCK",
      R = "REPLACE", Rv = "V-REPLACE",
      c = "COMMAND", cv = "EX", r = "PROMPT", rm = "MORE", ["r?"] = "CONFIRM",
      ["!"] = "SHELL", t = "TERMINAL",
    }
    local ViMode = pill(
      function(self) return mode_colors[self.mode:sub(1, 1)] or "blue" end,
      { provider = function(self) return " " .. (mode_names[self.mode] or self.mode:upper()) .. " " end }
    )
    ViMode.init = function(self) self.mode = vim.fn.mode(1) end
    ViMode.update = {
      "ModeChanged",
      pattern = "*:*",
      callback = vim.schedule_wrap(function() vim.cmd("redrawstatus") end),
    }

    local Git = {
      condition = conditions.is_git_repo,
      init = function(self) self.status = vim.b.gitsigns_status_dict end,
      hl = { fg = "orange" },
      { provider = function(self) return " " .. self.status.head .. " " end, hl = { bold = true } },
      {
        provider = function(self)
          local c = self.status.added or 0
          return c > 0 and ("+" .. c .. " ") or ""
        end,
        hl = { fg = "git_add" },
      },
      {
        provider = function(self)
          local c = self.status.changed or 0
          return c > 0 and ("~" .. c .. " ") or ""
        end,
        hl = { fg = "git_change" },
      },
      {
        provider = function(self)
          local c = self.status.removed or 0
          return c > 0 and ("-" .. c .. " ") or ""
        end,
        hl = { fg = "git_del" },
      },
    }

    local FileNameBlock = { init = function(self) self.filename = vim.api.nvim_buf_get_name(0) end }
    local FileIcon = {
      init = function(self)
        local ext = vim.fn.fnamemodify(self.filename, ":e")
        self.icon, self.icon_color =
          require("nvim-web-devicons").get_icon_color(self.filename, ext, { default = true })
      end,
      provider = function(self) return self.icon and (self.icon .. " ") end,
      hl = function(self) return { fg = self.icon_color } end,
    }
    local FileName = {
      provider = function(self)
        local name = vim.fn.fnamemodify(self.filename, ":t")
        return name == "" and "[No Name]" or name
      end,
      hl = { fg = "fg" },
    }
    local FileFlags = {
      {
        condition = function() return vim.bo.modified end,
        provider = " ●",
        hl = { fg = "green" },
      },
      {
        condition = function() return not vim.bo.modifiable or vim.bo.readonly end,
        provider = "  ",
        hl = { fg = "orange" },
      },
    }
    FileNameBlock = utils.insert(FileNameBlock, FileIcon, FileName, FileFlags, { provider = "%<" })

    local Navic = {
      condition = function()
        local ok, navic = pcall(require, "nvim-navic")
        return ok and navic.is_available()
      end,
      provider = function() return require("nvim-navic").get_location() end,
      hl = { fg = "gray" },
      update = "CursorMoved",
    }

    local diag_icons = { error = " ", warn = " ", info = " ", hint = "󰌶 " }
    local Diagnostics = {
      condition = conditions.has_diagnostics,
      init = function(self)
        local sev = vim.diagnostic.severity
        self.errors = #vim.diagnostic.get(0, { severity = sev.ERROR })
        self.warns  = #vim.diagnostic.get(0, { severity = sev.WARN })
        self.infos  = #vim.diagnostic.get(0, { severity = sev.INFO })
        self.hints  = #vim.diagnostic.get(0, { severity = sev.HINT })
      end,
      update = { "DiagnosticChanged", "BufEnter" },
      { provider = function(self) return self.errors > 0 and (diag_icons.error .. self.errors .. " ") end, hl = { fg = "red" } },
      { provider = function(self) return self.warns  > 0 and (diag_icons.warn  .. self.warns  .. " ") end, hl = { fg = "orange" } },
      { provider = function(self) return self.infos  > 0 and (diag_icons.info  .. self.infos  .. " ") end, hl = { fg = "blue" } },
      { provider = function(self) return self.hints  > 0 and (diag_icons.hint  .. self.hints  .. " ") end, hl = { fg = "cyan" } },
    }
    local LSPActive = {
      condition = conditions.lsp_attached,
      provider = function()
        local clients = vim.lsp.get_clients({ bufnr = 0 })
        if #clients == 0 then return "" end
        local names = vim.tbl_map(function(c) return c.name end, clients)
        return " " .. table.concat(names, " ")
      end,
      hl = { fg = "green" },
      update = { "LspAttach", "LspDetach", "BufEnter" },
    }
    local LSPProgress = {
      provider = function() return vim.ui.progress_status() or "" end,
      hl = { fg = "gray" },
    }

    local FileType = {
      init = function(self)
        local name = vim.api.nvim_buf_get_name(0)
        local ext = vim.fn.fnamemodify(name, ":e")
        self.icon, self.icon_color =
          require("nvim-web-devicons").get_icon_color(name, ext, { default = true })
      end,
      { provider = function(self) return self.icon and (self.icon .. " ") end, hl = function(self) return { fg = self.icon_color } end },
      { provider = function() return vim.bo.filetype end, hl = { fg = "blue", bold = true } },
    }
    local FilePercent = { provider = " %P " }

    local Ruler = pill("blue", { provider = " %l:%c " })

    local cc = { count = 0, frame = 1, name = nil }
    local cc_frames = { "⣷", "⣯", "⣟", "⡿", "⢿", "⣻", "⣽", "⣾" }
    local cc_timer = nil
    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("HeirlineCodeCompanion", { clear = true }),
      pattern = { "CodeCompanionRequestStarted", "CodeCompanionRequestFinished" },
      callback = function(args)
        if args.match == "CodeCompanionRequestStarted" then
          cc.count = cc.count + 1
          local adapter = (args.data or {}).adapter
          cc.name = adapter and (adapter.formatted_name or adapter.name) or "CodeCompanion"
          if not cc_timer then
            cc_timer = vim.uv.new_timer()
            cc_timer:start(0, 100, vim.schedule_wrap(function()
              cc.frame = cc.frame % #cc_frames + 1
              vim.cmd("redrawstatus")
            end))
          end
        else
          cc.count = math.max(0, cc.count - 1)
          if cc.count == 0 and cc_timer then
            cc_timer:stop()
            cc_timer:close()
            cc_timer = nil
          end
        end
        vim.cmd("redrawstatus")
      end,
    })
    local CodeCompanion = {
      condition = function() return cc.count > 0 end,
      provider = function() return " " .. cc_frames[cc.frame] .. " " .. cc.name .. " " end,
      hl = { fg = "purple", bold = true },
    }

    local DefaultStatusline = {
      ViMode, Space, Git, Space, FileNameBlock, Space, Navic,
      Align,
      CodeCompanion, Space, Diagnostics, Space, LSPActive, Space, LSPProgress, Space, FileType, FilePercent, Ruler,
    }

    local SpecialStatusline = {
      condition = function()
        return conditions.buffer_matches({
          buftype  = { "nofile", "prompt", "help", "quickfix", "terminal" },
          filetype = { "^git.*", "fugitive", "toggleterm", "fzf", "qf" },
        })
      end,
      ViMode, Space,
      { provider = function() return " " .. vim.bo.filetype:upper() .. " " end, hl = { fg = "fg", bold = true } },
      Align,
      Ruler,
    }

    local function IsCodeCompanion()
      return package.loaded.codecompanion and vim.bo.filetype == "codecompanion"
    end
    local function cc_stat(icon, key)
      return {
        condition = function(self) return (self.meta[key] or 0) > 0 end,
        provider = function(self) return " " .. icon .. " " .. self.meta[key] .. " " end,
        hl = { fg = "gray" },
      }
    end
    vim.api.nvim_create_autocmd("User", {
      group = "HeirlineCodeCompanion",
      pattern = { "CodeCompanionChatOpened", "CodeCompanionChatModel", "CodeCompanionChatDone" },
      callback = vim.schedule_wrap(function() vim.cmd("redrawstatus") end),
    })
    local CodeCompanionStatusline = {
      condition = IsCodeCompanion,
      init = function(self)
        self.meta = (_G.codecompanion_chat_metadata or {})[vim.api.nvim_get_current_buf()] or {}
      end,
      ViMode, Space,
      {
        provider = function(self)
          local a = self.meta.adapter
          return "󰚩 " .. ((a and a.name) or "CodeCompanion") .. " "
        end,
        hl = { fg = "purple", bold = true },
      },
      Align,
      cc_stat("Σ", "tokens"),
      cc_stat("⟳", "cycles"),
      cc_stat("⧉", "context_items"),
      cc_stat("⚒", "tools"),
      Ruler,
    }

    local StatusLines = {
      hl = function() return conditions.is_active() and "StatusLine" or "StatusLineNC" end,
      fallthrough = false,
      CodeCompanionStatusline,
      SpecialStatusline,
      DefaultStatusline,
    }


    local TablineFileIcon = {
      init = function(self)
        local ext = vim.fn.fnamemodify(self.filename, ":e")
        self.icon, self.icon_color =
          require("nvim-web-devicons").get_icon_color(self.filename, ext, { default = true })
      end,
      provider = function(self) return self.icon and (self.icon .. " ") end,
      hl = function(self) return { fg = self.icon_color } end,
    }

    local TablineFileName = {
      provider = function(self)
        local name = vim.fn.fnamemodify(self.filename, ":t")
        return name == "" and "[No Name]" or name
      end,
      hl = function(self) return { bold = self.is_active or self.is_visible } end,
    }

    local TablineFileFlags = {
      {
        condition = function(self)
          return vim.api.nvim_get_option_value("modified", { buf = self.bufnr })
        end,
        provider = " ●",
        hl = { fg = "green" },
      },
      {
        condition = function(self)
          return not vim.api.nvim_get_option_value("modifiable", { buf = self.bufnr })
            or vim.api.nvim_get_option_value("readonly", { buf = self.bufnr })
        end,
        provider = " ",
        hl = { fg = "orange" },
      },
    }

    local TablineFileNameBlock = {
      init = function(self) self.filename = vim.api.nvim_buf_get_name(self.bufnr) end,
      hl = function(self) return self.is_active and "TabLineSel" or "TabLine" end,
      on_click = {
        callback = function(_, minwid, _, button)
          if button == "m" then
            vim.schedule(function()
              vim.api.nvim_buf_delete(minwid, { force = false })
              vim.cmd.redrawtabline()
            end)
          else
            vim.api.nvim_win_set_buf(0, minwid)
          end
        end,
        minwid = function(self) return self.bufnr end,
        name = "heirline_tabline_buffer_callback",
      },
      { provider = " " }, TablineFileIcon, TablineFileName, TablineFileFlags,
    }

    local TablineCloseButton = {
      condition = function(self)
        return not vim.api.nvim_get_option_value("modified", { buf = self.bufnr })
      end,
      { provider = " " },
      {
        provider = "",
        hl = { fg = "gray" },
        on_click = {
          callback = function(_, minwid)
            vim.schedule(function()
              vim.api.nvim_buf_delete(minwid, { force = false })
              vim.cmd.redrawtabline()
            end)
          end,
          minwid = function(self) return self.bufnr end,
          name = "heirline_tabline_close_buffer_callback",
        },
      },
    }

    local TablineBufferBlock = utils.surround({ "", "" }, function(self)
      return self.is_active and utils.get_highlight("TabLineSel").bg
        or utils.get_highlight("TabLine").bg
    end, { TablineFileNameBlock, TablineCloseButton })

    local BufferLine = utils.make_buflist(
      TablineBufferBlock,
      { provider = " ", hl = { fg = "gray" } },
      { provider = " ", hl = { fg = "gray" } }
    )

    local Tabpage = {
      provider = function(self) return "%" .. self.tabnr .. "T " .. self.tabnr .. " %T" end,
      hl = function(self) return self.is_active and "TabLineSel" or "TabLine" end,
    }
    local TabpageClose = { provider = "%999X  %X", hl = "TabLine" }
    local TabPages = {
      condition = function() return #vim.api.nvim_list_tabpages() >= 2 end,
      { provider = "%=" },
      utils.make_tablist(Tabpage),
      TabpageClose,
    }

    local TabLine = { BufferLine, TabPages }

    heirline.setup({ statusline = StatusLines, tabline = TabLine })
    heirline.load_colors(setup_colors())

    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("Heirline", { clear = true }),
      callback = function() utils.on_colorscheme(setup_colors) end,
    })
  '';
}
