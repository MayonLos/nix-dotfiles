-- Gate render-markdown's latex handler so it only renders what fits where the
-- formula actually sits.
--
-- utftex draws real two-level boxes. render-markdown puts the extra rows in
-- virt_lines around the *buffer* line, which is right for a display block on
-- its own line and unreadable inline: on a wrapped prose paragraph the
-- numerator and the denominator end up several screen rows apart with the text
-- in between, and every multi-row formula on one line shares a single merged
-- virt_lines mark, so two fractions in one sentence collide.
--
-- So: a formula that owns its line goes to the builtin handler and gets the
-- full box. An inline one has to come back exactly one row tall, and there are
-- three ways to get there, tried in order.
local M = {}

local builtin = require("render-markdown.handler.latex")

-- Read one latex argument starting at i: a braced group, a command, or a
-- single character. Returns the argument body and the index just past it.
local function read_arg(s, i)
  i = s:find("%S", i) or #s + 1
  local c = s:sub(i, i)
  if c == "{" then
    local depth = 0
    for j = i, #s do
      local ch = s:sub(j, j)
      if ch == "{" then
        depth = depth + 1
      elseif ch == "}" then
        depth = depth - 1
        if depth == 0 then
          return s:sub(i + 1, j - 1), j + 1
        end
      end
    end
    return s:sub(i + 1), #s + 1
  elseif c == "\\" then
    local cmd = s:match("^\\%a+", i) or s:sub(i, i + 1)
    return cmd, i + #cmd
  elseif c == "" then
    return "", i
  end
  return c, i + 1
end

-- A lone symbol, number or command already binds tighter than "/".
local function atom(s)
  return s:match("^%w+$") ~= nil or s:match("^\\%a+$") ~= nil
end

-- "a+b" has to be bracketed on either side of a slash; "10" or "Ts" only under
-- one. A leading sign is not an operator.
local function has_term_break(s)
  return s:sub(2):find("[+-]") ~= nil
end

-- \frac{a}{b} and \sqrt{a} are what force utftex to stack rows. Rewriting them
-- as a/(b) and √(a) keeps the formula on one line without changing what it
-- means -- which is exactly what latex2text gets wrong when it drops the
-- brackets and turns \frac{1}{1+GH} into "1/1 + GH".
local linearise
linearise = function(expr)
  local out, i = {}, 1
  while i <= #expr do
    local frac = expr:match("^\\[dt]?frac", i)
    local sqrt = expr:match("^\\sqrt", i)
    if frac then
      local a, j = read_arg(expr, i + #frac)
      local b, k = read_arg(expr, j)
      a, b = vim.trim(linearise(a)), vim.trim(linearise(b))
      local bracket_a = has_term_break(a) or a:find("/", 1, true) ~= nil
      local text = (bracket_a and "(" .. a .. ")" or a) .. "/" .. (atom(b) and b or "(" .. b .. ")")
      -- \frac{A}{2}t^2 linearises to A/2t^2, which reads as A/(2t^2). Bracket
      -- the quotient whenever something multiplies onto its right.
      local after = expr:find("%S", k)
      if after and expr:sub(after, after):match("[%w\\(]") then
        text = "(" .. text .. ")"
      end
      out[#out + 1] = text
      i = k
    elseif sqrt then
      local a, j = read_arg(expr, i + #sqrt)
      a = vim.trim(linearise(a))
      out[#out + 1] = "\\surd" .. (atom(a) and a or "(" .. a .. ")")
      i = j
    else
      out[#out + 1] = expr:sub(i, i)
      i = i + 1
    end
  end
  return table.concat(out)
end

-- latex2text drops the braces around a multi-token script, turning e^{A\cdot0}
-- into "e^A·0". Brackets survive it, so swap them in first. utftex does not
-- need this and renders the bracket badly, hence a separate pass.
local bracket_scripts
bracket_scripts = function(expr)
  local out, i = {}, 1
  while i <= #expr do
    local c = expr:sub(i, i)
    if (c == "^" or c == "_") and expr:sub(i + 1, i + 1) == "{" then
      local a, j = read_arg(expr, i + 1)
      a = bracket_scripts(a)
      -- Only a script holding an operator can be misread once the braces are
      -- gone: R_{DS(on)} is fine as R_DS(on), e^{-\tau s} is not.
      local rebinds = a:find("[-+*/]") ~= nil or a:find("\\cdot") ~= nil or a:find("\\times") ~= nil
      out[#out + 1] = rebinds and (c .. "(" .. a .. ")") or (c .. a)
      i = j
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function one_line(cmd, expr)
  local ok, res = pcall(function()
    return vim.system(cmd, { stdin = expr, text = true }):wait()
  end)
  if not ok or res.code ~= 0 then
    return nil
  end
  local out = (res.stdout or ""):gsub("%s+$", "")
  if out == "" or out:find("\n") then
    return nil
  end
  return out
end

local cache = {}

-- "builtin" -> hand the node to the builtin handler
-- string    -> render inline with this text ourselves
-- false     -> leave the source untouched
local function classify(expr)
  local hit = cache[expr]
  if hit ~= nil then
    return hit
  end

  local result = false
  local linear = linearise(expr)
  if one_line({ "utftex" }, expr) then
    -- Fits as it stands: let the builtin render it, so render-markdown keeps
    -- accounting for the width it concealed when it sizes table columns.
    result = "builtin"
  elseif linear ~= expr and one_line({ "utftex" }, linear) then
    result = one_line({ "utftex" }, linear)
  elseif not expr:find("\\overline") then
    -- Last resort, symbol substitution only. Barred names are excluded because
    -- latex2text silently drops the bar, and \overline{AB} without it is a
    -- different logic expression than the one written.
    result = one_line({ "latex2text" }, bracket_scripts(linear)) or false
  end

  cache[expr] = result
  return result
end

-- The table handler sizes columns from the buffer text and only accounts for
-- the marks render-markdown made itself, so a cell shortened here drags its
-- right border left. Give the width back as spaces at the end of the cell,
-- where they sit just before the closing pipe and are invisible.
local function pad_mark(row, line, end_col, lost)
  local cell_end = line:find("|", end_col + 1, true)
  return {
    conceal = true,
    start_row = row,
    start_col = cell_end and cell_end - 1 or #line,
    opts = {
      virt_text = { { string.rep(" ", lost), "RenderMarkdownMath" } },
      virt_text_pos = "inline",
    },
  }
end

local function inline_mark(row, col, end_row, end_col, text)
  return {
    conceal = true,
    start_row = row,
    start_col = col,
    opts = {
      end_row = end_row,
      end_col = end_col,
      conceal = "",
      virt_text = { { text, "RenderMarkdownMath" } },
      virt_text_pos = "inline",
    },
  }
end

local pending = {}

function M.parse(ctx)
  local buf = ctx.buf
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local batch = pending[buf]
  -- A pass interrupted by an edit never reached ctx.last; its roots are stale,
  -- so start over rather than replay them into the new tree.
  if not batch or batch.tick ~= tick then
    batch = { tick = tick, roots = {}, marks = {} }
    pending[buf] = batch
  end

  local row, col, end_row, end_col = ctx.root:range()
  local text = vim.treesitter.get_node_text(ctx.root, buf)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""

  if row ~= end_row or vim.trim(line) == vim.trim(text) then
    batch.roots[#batch.roots + 1] = ctx.root
  else
    local verdict = classify(vim.trim((text:gsub("^%$+", ""):gsub("%$+$", ""))))
    if verdict == "builtin" then
      batch.roots[#batch.roots + 1] = ctx.root
    elseif verdict then
      local lost = 0
      if line:match("^%s*|") then
        lost = vim.fn.strdisplaywidth(text) - vim.fn.strdisplaywidth(verdict)
      end
      if lost >= 0 then
        batch.marks[#batch.marks + 1] = inline_mark(row, col, end_row, end_col, verdict)
        if lost > 0 then
          batch.marks[#batch.marks + 1] = pad_mark(row, line, end_col, lost)
        end
      end
    end
  end

  if not ctx.last then
    return {}
  end
  pending[buf] = nil

  -- The builtin buffers every root it is handed and converts the whole batch in
  -- one utftex call when ctx.last is set. Because the rejected roots never
  -- reach it, the real last root may be one of those and the batch would never
  -- be flushed -- so replay the kept roots and set last on our own final one.
  local marks = batch.marks
  for i, root in ipairs(batch.roots) do
    local ok, out = pcall(builtin.parse, { buf = buf, root = root, last = i == #batch.roots })
    if ok then
      vim.list_extend(marks, out)
    end
  end
  return marks
end

return M
