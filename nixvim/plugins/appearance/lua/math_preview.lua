--- Live LaTeX preview float.
---
--- snacks.nvim already has a document hover that does most of this, and it is
--- not usable for writing maths: `snacks/image/doc.lua:377` closes the float
--- the moment `vim.fn.mode() ~= "n"`, and `_attach` only ever registers
--- `CursorMoved` -- so the preview is gone for exactly as long as you are
--- typing the formula. Neither is configurable. When pdflatex rejects the
--- formula nothing appears at all: the failure is a `Snacks.notify` at best,
--- so a typo reads as "the renderer is broken".
---
--- This drives snacks' own pieces instead of replacing them, so the on-disk
--- cache, the LaTeX template and the palette colour all stay shared:
---   * `Snacks.image.doc.at_cursor` finds the formula under the cursor,
---   * `Snacks.image.convert.convert` renders it and reports failure,
---   * `Snacks.image.placement.new` puts the PNG in our float.
--- Only the *when* and the *error path* are ours.
---
--- snacks' own doc handling must be off for this to be the only thing
--- drawing: `doc.inline = false` and `doc.float = false` in snacks.nix make
--- `_attach` return early while leaving the API above callable.

local M = {}

local uv = vim.uv or vim.loop

-- Same set snacks attaches to, minus the ones with no maths.
local FILETYPES = {
  markdown = true,
  tex = true,
  latex = true,
  typst = true,
  norg = true,
  codecompanion = true,
}

-- Long enough that holding a key down does not queue a pdflatex run per
-- keystroke, short enough to feel live. Renders are content-addressed in
-- ~/.cache/nvim/snacks/image, so retyping a formula you already had costs
-- nothing.
local DEBOUNCE = 250

---@type {win?:table, img?:table, src?:string, kind?:"image"|"error"}
local state = {}
local timer ---@type any
local augroup = vim.api.nvim_create_augroup("math_preview", { clear = true })

local function close()
  if state.img then
    pcall(function()
      state.img:close()
    end)
  end
  if state.win then
    pcall(function()
      state.win:close()
    end)
  end
  state = {}
end

--- Pull the actual complaint out of pdflatex's log.
---
--- The log sits beside the generated .tex because snacks runs pdflatex with
--- `-output-directory={cache}` (snacks/image/convert.lua, the `tex` command).
--- LaTeX's error format is stable and has been for decades: the message is a
--- line starting with `!`, and the offending input is echoed a few lines later
--- as `l.<n> <text>`. Everything between is TeX's own bookkeeping.
---@param src string path to the generated .tex
---@return string[]?
local function latex_error(src)
  local log = src:gsub("%.tex$", ".log")
  local fd = io.open(log, "r")
  if not fd then
    return nil
  end
  local out = {} ---@type string[]
  local after = 0
  for line in fd:lines() do
    if line:sub(1, 1) == "!" then
      out[#out + 1] = line
      after = 6
    elseif after > 0 then
      -- `l.12 \frac{1}{s} \badcmd` -- the line TeX choked on.
      if line:match("^l%.%d+") then
        out[#out + 1] = vim.trim(line)
        after = 0
      end
      after = after - 1
    end
    if #out >= 6 then
      break
    end
  end
  fd:close()
  return #out > 0 and out or nil
end

---@param src string
---@param lines string[]
local function show_error(src, lines)
  close()
  state.src = src
  local width = 0
  for i, l in ipairs(lines) do
    lines[i] = l:gsub("\t", "  ")
    width = math.max(width, vim.fn.strdisplaywidth(lines[i]))
  end
  width = math.min(math.max(width, 20), math.floor(vim.o.columns * 0.8))

  state.kind = "error"
  state.win = Snacks.win({
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = math.min(#lines, 8),
    border = "rounded",
    focusable = false,
    enter = false,
    backdrop = false,
    text = lines,
    bo = { filetype = "tex", modifiable = false },
    -- DiagnosticError on the border rather than on the text: the message is
    -- already the point, a red wall of it is just harder to read.
    wo = {
      wrap = false,
      winhighlight = "Normal:NormalFloat,FloatBorder:DiagnosticError",
    },
  })
end

---@param src string
local function show_image(src)
  close()
  state.kind = "image"
  state.src = src

  -- Lifted from snacks' own hover (image/doc.lua): the window has to be
  -- created hidden, because its size is only known once the placement has
  -- measured the image, which happens in `on_update_pre`.
  local win = Snacks.win(Snacks.win.resolve(Snacks.image.config.doc, "snacks_image", {
    show = false,
    enter = false,
    wo = { winblend = Snacks.image.terminal.env().placeholders and 0 or nil },
  }))
  win:open_buf()
  state.win = win

  local shown = false
  state.img = Snacks.image.placement.new(
    win.buf,
    src,
    Snacks.config.merge({}, Snacks.image.config.doc, {
      inline = false,
      on_update_pre = function()
        if shown or not state.img then
          return
        end
        shown = true
        local loc = state.img:state().loc
        win.opts.width = loc.width
        win.opts.height = loc.height
        win:show()
      end,
    })
  )
end

local function update()
  if not FILETYPES[vim.bo.filetype] then
    return close()
  end

  local buf = vim.api.nvim_get_current_buf()

  local ok = pcall(Snacks.image.doc.at_cursor, function(src)
    if not src then
      return close()
    end
    if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_get_current_buf() ~= buf then
      return close()
    end
    -- Already showing this exact formula: leave it alone rather than
    -- rebuilding the float on every cursor nudge inside it.
    --
    -- This has to cover the error float too, not just the image one. Guarding
    -- on `kind == "image"` meant a formula that does not compile re-entered
    -- the convert pipeline every 250 ms for as long as the cursor sat in it --
    -- invisible, because the float it produced was identical each time, and
    -- the cost was a pdflatex run per tick.
    if state.src == src and state.win and state.win:valid() then
      return
    end

    -- `convert.convert()` only *builds* the pipeline -- `Convert.new` ends at
    -- `self:resolve()` and nothing runs until someone calls `:run()`. snacks
    -- does that from `Image:run()`, which we are not going through. Measured
    -- headless first: without the `:run()` below, `on_done` never fires and no
    -- pdflatex log is ever written, so every formula silently looked fine.
    --
    -- `resolve()` drops steps whose output is already on disk, so a cached
    -- formula ends with zero steps and `run()` calls `on_done` straight away.
    Snacks.image.convert
      .convert({
        src = src,
        on_done = function(convert)
          vim.schedule(function()
            -- The cursor may have moved on while pdflatex was running.
            if vim.api.nvim_get_current_buf() ~= buf then
              return
            end
            -- The log is the authority here, not `convert:error()`.
            -- snacks runs pdflatex with `-interaction=nonstopmode`, and its
            -- `tex` step has an `on_error` that returns true whenever a PDF
            -- came out anyway (convert.lua, the `tex` command) -- so a
            -- formula with a real syntax error converts "successfully" into a
            -- partial image and `convert:error()` stays nil. Measured on
            -- `$$\frac{1}{s} \badcommand{x}$$`: error=nil, while the log
            -- held `! Undefined control sequence.` and the offending line.
            -- Showing that partial image would be worse than showing nothing,
            -- because it looks like the formula was accepted.
            local errs = latex_error(src)
            if errs then
              show_error(src, errs)
            elseif convert:error() then
              show_error(src, { "! LaTeX failed", vim.trim(convert:error()) })
            else
              show_image(src)
            end
          end)
        end,
      })
      :run()
  end)

  if not ok then
    -- `at_cursor` walks the treesitter tree, which can be mid-reparse while
    -- the buffer is being edited. Dropping one frame is the right answer; the
    -- next keystroke schedules another.
    return
  end
end

local function schedule()
  timer = timer or assert(uv.new_timer())
  timer:stop()
  timer:start(DEBOUNCE, 0, vim.schedule_wrap(update))
end

function M.setup()
  -- `CursorMovedI` and `TextChangedI` are the whole point: they are what
  -- snacks does not listen to, and they are what makes this live while the
  -- formula is being written.
  vim.api.nvim_create_autocmd(
    { "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "InsertLeave" },
    {
      group = augroup,
      callback = schedule,
    }
  )

  -- Nothing to preview if the window or buffer is gone. Immediate, not
  -- debounced -- a float left over another buffer is worse than a late one.
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave", "CmdlineEnter" }, {
    group = augroup,
    callback = close,
  })

  vim.keymap.set("n", "<leader>mp", function()
    update()
  end, { desc = "Math preview (refresh)" })
end

return M
