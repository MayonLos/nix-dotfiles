{
  # Opening links from prose, not from code. The notes vault under
  # ~/Documents/notes is a pile of markdown checkbox bullets whose payload is a
  # link — `- [ ] [title](https://…) — reason` — so the two things worth doing
  # are "open the one under the cursor" and "show me every link in here and let
  # me pick several". `<leader>fU` covers the vault whenever cwd is inside it,
  # and `:Urls ~/Documents/notes` reaches it from anywhere.
  #
  # Neovim 0.12 already binds `gx` to `vim.ui.open(vim.ui._get_urls())`, and
  # xdg-open resolves to zen-beta on this host, so the plumbing works. What is
  # replaced here is the *detection*: `_get_urls` wants the cursor on the URL
  # itself, and in a bullet like the one above the cursor is almost always on
  # the title text or on the checkbox instead. It also has no notion of the
  # trailing CJK punctuation these notes are full of. Everything below is a
  # line scanner, so no extra plugin is pulled in — the picker rides on
  # fzf-lua, which is already here.

  extraConfigLua = ''
    local urls = {}
    _G.urls = urls

    -- Sentence punctuation and markdown wrappers that sit next to a URL
    -- without belonging to it. `*` is here for `**bold link**`.
    local ASCII_TRAILERS = "[%.,;:!%?'\"%*%]}>]"

    -- Cut by codepoint, not by byte: a URL may legitimately contain non-ASCII
    -- (`https://zh.wikipedia.org/wiki/控制论` has to survive), so only these
    -- specific marks end one, not "every byte above 0x7f".
    local CJK_TERMINATORS = {
      "，", "。", "；", "：", "！", "？", "、", "…",
      "（", "）", "【", "】", "「", "」", "《", "》", "“", "”", "　",
    }

    -- These never appear inside a real URL — they would be percent-encoded —
    -- so one always ends the URL, including mid-run: `…/x，还有` has no ASCII
    -- space to stop the match at, and trimming only the tail would keep 还有.
    local function cut_at_cjk(url)
      local cut
      for _, c in ipairs(CJK_TERMINATORS) do
        local s = url:find(c, 1, true)
        if s and (not cut or s < cut) then
          cut = s
        end
      end
      return cut and url:sub(1, cut - 1) or url
    end

    local function strip_once(url)
      -- A closing paren ends the URL only when nothing inside opened it:
      -- markdown wraps every link in `(...)`, but Wikipedia-style URLs carry
      -- balanced parens that have to survive.
      if url:sub(-1) == ")" then
        local _, opens = url:gsub("%(", "")
        local _, closes = url:gsub("%)", "")
        if closes > opens then
          return url:sub(1, -2)
        end
      end
      return (url:gsub(ASCII_TRAILERS .. "$", ""))
    end

    local function trim_url(url)
      url = cut_at_cjk(url)
      while true do
        local next_url = strip_once(url)
        if next_url == url then
          return url
        end
        url = next_url
      end
    end

    -- Earliest URL-ish run at or after `init`. `www.` without a scheme counts;
    -- it is flagged so the caller can prepend https.
    local function next_match(line, init)
      local s, e = line:find("https?://%S+", init)
      local ws, we = line:find("www%.[%w%-]+%.%S+", init)
      if ws and (not s or ws < s) then
        return ws, we, true
      end
      if s then
        return s, e, false
      end
      return nil
    end

    --- Every URL on one line, with 1-based byte columns and the markdown link
    --- text when the URL is the destination of a `[title](url)`.
    function urls.scan(line)
      local found, init = {}, 1
      while init <= #line do
        local s, e, bare = next_match(line, init)
        if not s then
          break
        end
        local url = trim_url(line:sub(s, e))
        if #url > 0 then
          table.insert(found, {
            url = bare and ("https://" .. url) or url,
            from = s,
            to = s + #url - 1,
            title = line:sub(1, s - 1):match("%[([^%]]*)%]%($"),
          })
        end
        init = e + 1
      end
      return found
    end

    function urls.open(url, quiet)
      local proc, err = vim.ui.open(url)
      if not proc then
        vim.notify("Cannot open " .. url .. ": " .. tostring(err), vim.log.levels.ERROR)
        return false
      end
      if not quiet then
        vim.notify(url, vim.log.levels.INFO, { title = "Opened" })
      end
      return true
    end

    -- --- gx -------------------------------------------------------------

    function urls.gx()
      local line = vim.api.nvim_get_current_line()
      local col = vim.api.nvim_win_get_cursor(0)[2] + 1
      local found = urls.scan(line)

      local pick
      for _, u in ipairs(found) do
        if col >= u.from and col <= u.to then
          pick = u
          break
        end
      end
      -- Cursor on the link *text* or on the `- [ ]` checkbox: a notes bullet
      -- is about exactly one link, so the first one on the line is the one
      -- that was meant.
      pick = pick or found[1]

      if pick then
        return urls.open(pick.url)
      end

      -- No URL anywhere on the line: keep the built-in behaviour of opening
      -- whatever path sits under the cursor.
      local cfile = vim.fn.expand("<cfile>")
      if cfile ~= "" then
        return urls.open(cfile)
      end
      vim.notify("No URL under cursor", vim.log.levels.WARN)
    end

    function urls.gx_visual()
      local region = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
      vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)

      local text = table.concat(region, " ")
      local found = urls.scan(text)
      if #found == 0 then
        -- Selecting a bare `example.com` is a deliberate "open this": scan
        -- would not match it because there is no scheme and no `www.`.
        local candidate = vim.trim(text)
        if candidate:match("^[%w%-%.]+%.%a%a+[%w%-%./%?#=&%%]*$") then
          return urls.open("https://" .. candidate)
        end
        vim.notify("No URL in selection", vim.log.levels.WARN)
        return
      end
      for _, u in ipairs(found) do
        urls.open(u.url)
      end
    end

    -- --- collecting ------------------------------------------------------

    function urls.label(entry)
      if entry.title and entry.title ~= "" then
        return entry.title
      end
      -- No markdown title: fall back to the prose around the link, minus the
      -- link itself, so a bare URL still shows whatever context the line has.
      local rest = entry.text:gsub("https?://%S+", ""):gsub("www%.[%w%-]+%.%S+", "")
      rest = rest:gsub("^%s*[%-%*%+]%s*", "") -- bullet
      rest = rest:gsub("^%[[ xX]%]%s*", "") -- checkbox
      rest = rest:gsub("[%[%]%(%)]", "") -- leftovers of a stripped markdown link
      rest = vim.trim(rest:gsub("%s+", " "))
      -- The separator in these notes is an em dash, which is multibyte: it is
      -- matched literally, never inside a `[...]` class, because Lua classes
      -- match single bytes and would slice a Chinese character in half.
      rest = rest:gsub("^—%s*", ""):gsub("%s*—$", "")
      return vim.trim(rest)
    end

    function urls.from_buffer(bufnr)
      local out = {}
      local lines = vim.api.nvim_buf_get_lines(bufnr or 0, 0, -1, false)
      for lnum, line in ipairs(lines) do
        for _, u in ipairs(urls.scan(line)) do
          table.insert(out, { lnum = lnum, url = u.url, title = u.title, text = line })
        end
      end
      return out
    end

    function urls.from_dir(dir)
      dir = vim.fn.expand(dir)
      -- rg is on the profile PATH, same assumption fzf-lua already makes.
      local ok, res = pcall(function()
        return vim
          .system({ "rg", "--no-heading", "--with-filename", "--line-number", "--color=never", "-e", "https?://", "--", dir }, { text = true })
          :wait(15000)
      end)
      if not ok then
        vim.notify("rg is not available: " .. tostring(res), vim.log.levels.ERROR)
        return {}
      end
      -- Exit 1 is rg's "no matches", which is a legitimate empty result.
      if res.code ~= 0 and res.code ~= 1 then
        vim.notify("rg failed: " .. (res.stderr or ""), vim.log.levels.ERROR)
        return {}
      end

      local out = {}
      for _, hit in ipairs(vim.split(res.stdout or "", "\n", { trimempty = true })) do
        local file, lnum, text = hit:match("^(.-):(%d+):(.*)$")
        if file then
          for _, u in ipairs(urls.scan(text)) do
            table.insert(out, {
              file = file,
              lnum = tonumber(lnum),
              url = u.url,
              title = u.title,
              text = text,
            })
          end
        end
      end
      return out
    end

    -- --- picker ----------------------------------------------------------

    function urls.pick(entries, opts)
      if #entries == 0 then
        vim.notify("No URLs found", vim.log.levels.WARN)
        return
      end

      -- fzf-lua is lazy-loaded on `cmd`/`keys` by lz.n, so it has to be
      -- triggered before require, exactly like the vim.ui.select shim in
      -- plugins/navigation/fzf.nix.
      require("lz.n").trigger_load("fzf-lua")
      local fzf = require("fzf-lua")
      local ansi = require("fzf-lua.utils").ansi_codes

      -- Field 1 is the index and is hidden by --with-nth, which makes every
      -- entry unique no matter how many times the same URL appears and gives
      -- the actions a key back into `entries`.
      local display = {}
      for i, e in ipairs(entries) do
        local where = e.file and (vim.fn.fnamemodify(e.file, ":.") .. ":" .. e.lnum) or tostring(e.lnum)
        local parts = { ansi.magenta(where) }
        local text = urls.label(e)
        if text ~= "" then
          table.insert(parts, text)
        end
        table.insert(parts, ansi.blue(e.url))
        display[i] = tostring(i) .. "\t" .. table.concat(parts, "  ")
      end

      local function chosen(selected)
        local picked = {}
        for _, line in ipairs(selected or {}) do
          local i = tonumber(line:match("^(%d+)\t"))
          if i then
            table.insert(picked, entries[i])
          end
        end
        return picked
      end

      fzf.fzf_exec(display, {
        prompt = opts.prompt,
        fzf_opts = {
          ["--multi"] = true,
          ["--no-sort"] = true,
          ["--delimiter"] = "\\t",
          ["--with-nth"] = "2..",
        },
        actions = {
          -- Tab-select a handful of bullets, hit enter, read them all later.
          ["default"] = function(selected)
            local picked = chosen(selected)
            for _, e in ipairs(picked) do
              urls.open(e.url, #picked > 1)
            end
            if #picked > 1 then
              vim.notify(#picked .. " links opened", vim.log.levels.INFO)
            end
          end,
          ["ctrl-y"] = function(selected)
            local picked = vim.tbl_map(function(e)
              return e.url
            end, chosen(selected))
            vim.fn.setreg("+", table.concat(picked, "\n"))
            vim.notify(#picked .. " URL(s) yanked", vim.log.levels.INFO)
          end,
          -- Go to the line instead of the site — for editing the note, or for
          -- ticking the checkbox once the link has been read.
          ["ctrl-o"] = function(selected)
            local e = chosen(selected)[1]
            if not e then
              return
            end
            if e.file then
              vim.cmd.edit(vim.fn.fnameescape(e.file))
            end
            pcall(vim.api.nvim_win_set_cursor, 0, { e.lnum, 0 })
          end,
        },
      })
    end

    function urls.pick_buffer()
      urls.pick(urls.from_buffer(0), { prompt = "URLs (buffer)❯ " })
    end

    function urls.pick_dir(dir)
      dir = (dir and dir ~= "") and dir or vim.uv.cwd()
      urls.pick(urls.from_dir(dir), { prompt = "URLs " .. vim.fn.fnamemodify(dir, ":t") .. "❯ " })
    end

    vim.api.nvim_create_user_command("Urls", function(cmd)
      urls.pick_dir(cmd.args)
    end, { nargs = "?", complete = "dir", desc = "Pick a URL from a directory" })

    vim.api.nvim_create_user_command("UrlsBuffer", urls.pick_buffer, { desc = "Pick a URL from this buffer" })
  '';

  keymaps = [
    {
      mode = "n";
      key = "gx";
      action.__raw = "function() _G.urls.gx() end";
      options.desc = "Open URL under cursor";
    }
    {
      mode = "x";
      key = "gx";
      action.__raw = "function() _G.urls.gx_visual() end";
      options.desc = "Open URLs in selection";
    }
    {
      mode = "n";
      key = "<leader>fu";
      action.__raw = "function() _G.urls.pick_buffer() end";
      options.desc = "URLs in buffer";
    }
    {
      mode = "n";
      key = "<leader>fU";
      action.__raw = "function() _G.urls.pick_dir() end";
      options.desc = "URLs under cwd";
    }
  ];
}
