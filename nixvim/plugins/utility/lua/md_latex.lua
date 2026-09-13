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

local builtin

-- utftex 1.31 rendered {x+y}^2 as x+y² in the regression probe. Keeping
-- parentheses when removing a box preserves its grouping as well as its body.
local function read_group(s, i)
  i = s:find("%S", i) or #s + 1
  if s:sub(i, i) ~= "{" then
    return nil
  end
  local depth, j = 1, i + 1
  while j <= #s do
    local c = s:sub(j, j)
    if c == "%" then
      j = s:find("\n", j, true) or #s + 1
    elseif c == "\\" then
      j = j + 2
    else
      if c == "{" then
        depth = depth + 1
      elseif c == "}" then
        depth = depth - 1
        if depth == 0 then
          return s:sub(i + 1, j - 1), j + 1
        end
      end
      j = j + 1
    end
  end
end

local silent_drop = {
  overline = true,
  ne = true,
  iff = true,
  implies = true,
  bmod = true,
  deg = true,
}

local function has_command(expr, commands)
  local i = 1
  while i <= #expr do
    if expr:sub(i, i) == "\\" then
      local cmd = expr:match("^\\(%a+)", i)
      if cmd and commands[cmd] then
        return true
      end
      i = i + (cmd and #cmd + 1 or 2)
    else
      i = i + 1
    end
  end
  return false
end

-- Both labelled-arrow probes exited 1 in utftex; latex2text returned only
-- "a " for a \xrightarrow{b} and a \xleftarrow{b}. Keep the entire source.
local unsupported = { xrightarrow = true, xleftarrow = true }

-- The two matrix probes changed [21] to [2  1] and -2-3 to -2  -3 with
-- literal padding. This Lua pass is also used by the builtin's converter:
-- it fixes both paths without changing or rebuilding libtexprintf 1.31.
function M.preprocess(expr)
  if has_command(expr, unsupported) then
    return nil
  end
  local out, stack, depth, i = {}, {}, 0, 1
  while i <= #expr do
    local c = expr:sub(i, i)
    local cmd = c == "\\" and expr:match("^\\(%a+)", i)
    if c == "%" then
      local j = expr:find("\n", i, true) or #expr + 1
      out[#out + 1] = expr:sub(i, j - 1)
      i = j
    elseif cmd == "boxed" or cmd == "tag" then
      local body, j = read_group(expr, i + #cmd + 1)
      if not body then
        return nil
      end
      body = M.preprocess(body)
      if not body then
        return nil
      end
      -- a \tag{门1} exited 1; a (门1) exited 0 and kept the complete
      -- label. Parentheses retain the tag without an unsupported macro.
      out[#out + 1] = (cmd == "tag" and " (" or "(") .. body .. ")"
      i = j
    elseif cmd == "begin" or cmd == "end" then
      local env, j = read_group(expr, i + #cmd + 1)
      if not env then
        return nil
      end
      if cmd == "begin" then
        stack[#stack + 1] = {
          env = env,
          depth = depth,
          columns = env:match("matrix%*?$") ~= nil or env == "array" or env == "cases" or env == "aligned",
        }
      elseif #stack > 0 and stack[#stack].env == env then
        stack[#stack] = nil
      else
        return nil
      end
      out[#out + 1] = expr:sub(i, j - 1)
      i = j
    elseif c == "\\" then
      local length = cmd and #cmd + 1 or 2
      out[#out + 1] = expr:sub(i, i + length - 1)
      i = i + length
    else
      local env = stack[#stack]
      if c == "&" and env and env.columns and depth == env.depth then
        out[#out + 1] = " & "
      else
        out[#out + 1] = c
      end
      if c == "{" then
        depth = depth + 1
      elseif c == "}" then
        depth = depth - 1
      end
      i = i + 1
    end
  end
  if #stack > 0 then
    return nil
  end
  return table.concat(out)
end

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

-- The cache regression makes four inline/display queries for one fraction
-- with only two subprocesses: its original and its linearised input.
local conversions = {}

local function convert(cmd, expr)
  local key = cmd .. "\0" .. expr
  if conversions[key] ~= nil then
    return conversions[key]
  end
  local ok, res = pcall(function()
    return vim.system({ cmd }, { stdin = expr, text = true }):wait()
  end)
  local out = ok and res.code == 0 and (res.stdout or ""):gsub("%s+$", "") or false
  conversions[key] = out ~= "" and out or false
  return conversions[key]
end

local function one_line(out)
  return out and not out:find("\n") and out or false
end

local cache = {}

-- "builtin" -> hand the node to the builtin handler
-- string    -> render inline with this text ourselves
-- false     -> leave the source untouched
local function classify(expr, display)
  local key = (display and "display\0" or "inline\0") .. expr
  local hit = cache[key]
  if hit then
    return hit.value, hit.route
  end

  local result, route = false, "raw"
  local prepared = M.preprocess(expr)
  if prepared then
    local rendered = convert("utftex", prepared)
    if (display and rendered) or one_line(rendered) then
      -- Fits as it stands: let the builtin render it, so render-markdown keeps
      -- accounting for the width it concealed when it sizes table columns.
      result, route = "builtin", "builtin"
    else
      local linear = linearise(prepared)
      local flattened = linear ~= prepared and one_line(convert("utftex", linear))
      if flattened then
        result, route = flattened, "linearised-utftex"
      elseif not has_command(expr, silent_drop) then
        -- All six probes (overline, ne, iff, implies, bmod, deg) returned "a b"
        -- from latex2text 2.10 for a \macro{b}. A missing bar changes the logic
        -- expression; a missing relation changes the statement just as surely.
        result = one_line(convert("latex2text", bracket_scripts(linear)))
        if result then
          route = "latex2text"
        end
      end
    end
  end

  cache[key] = { value = result, route = route }
  return result, route
end

M.classify = classify

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
  builtin = builtin or require("render-markdown.handler.latex")
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

  local display = row ~= end_row or vim.trim(line) == vim.trim(text)
  local verdict = classify(vim.trim((text:gsub("^%$+", ""):gsub("%$+$", ""))), display)
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

  if not ctx.last then
    return {}
  end
  pending[buf] = nil

  -- The replay regression keeps one builtin root when the final root is
  -- rejected. render-markdown 8.12.0 waits for ctx.last to convert its pending
  -- inputs, so the final kept root must flush the batch itself.
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
