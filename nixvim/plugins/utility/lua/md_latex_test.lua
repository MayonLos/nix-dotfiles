vim.env.NVIM_LOG_FILE = "/tmp/md_latex_test.log"
local path = "nixvim/plugins/utility/lua/md_latex.lua"
local failures, passes = 0, 0
local function check(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passes = passes + 1
    print("PASS " .. name)
  else
    failures = failures + 1
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end
local function eq(actual, expected)
  assert(actual == expected, vim.inspect(actual) .. " ~= " .. vim.inspect(expected))
end
local function contains(s, needle)
  assert(type(s) == "string" and s:find(needle, 1, true), vim.inspect(s) .. " lacks " .. needle)
end
local system = vim.system
local calls = {}
vim.system = function(cmd, opts)
  assert(opts and type(opts.stdin) == "string", "formula must be on stdin")
  eq(#cmd, 1)
  calls[#calls + 1] = { cmd = cmd[1], expr = opts.stdin }
  return system(cmd, opts)
end
local function run(cmd, expr)
  local result = vim.system({ cmd }, { stdin = expr, text = true }):wait()
  eq(result.code, 0)
  return result.stdout:gsub("%s+$", "")
end
local builtin_loads, roots = 0, {}
local m
package.loaded["render-markdown.handler.latex"] = nil
package.preload["render-markdown.handler.latex"] = function()
  builtin_loads = builtin_loads + 1
  return {
    parse = function(ctx)
      roots[#roots + 1] = ctx
      local expr = vim.trim(ctx.root.text:gsub("^%$+", ""):gsub("%$+$", ""))
      local output = run("utftex", assert(m.preprocess(expr)))
      return { { output = output } }
    end,
  }
end
check("cold module load does not require render-markdown", function()
  m = dofile(path)
  eq(builtin_loads, 0)
end)
if not m then
  os.exit(1)
end
local function rendered(expr, display)
  local value = m.classify(expr, display)
  if value == "builtin" then
    return run("utftex", assert(m.preprocess(expr)))
  end
  return value
end
local boxed = [[\boxed{\text{传函稳定}\ \ne\ \text{系统稳定}}]]
for _, display in ipairs({ false, true }) do
  check("boxed stability keeps inequality, display=" .. tostring(display), function()
    local value = rendered(boxed, display)
    contains(value, "≠")
    contains(value, "传函稳定")
    contains(value, "系统稳定")
  end)
end
check("single-row matrix columns remain distinct", function()
  eq(rendered([[\begin{bmatrix}2&1\end{bmatrix}]]), "[2  1]")
end)
check("display matrix keeps negative columns and two rows", function()
  local value = rendered([[\begin{bmatrix}0&1\\-2&-3\end{bmatrix}]], true)
  contains(value, "-2  -3")
  contains(value, "\n")
end)
for _, macro in ipairs({ "ne", "iff", "implies", "bmod", "deg", "overline" }) do
  check(macro .. " never reaches latex2text, including display fallback", function()
    eq(run("latex2text", "a \\" .. macro .. "{b}"), "a b")
    calls = {}
    m.classify("a \\" .. macro .. "{b}")
    for _, display in ipairs({ false, true }) do
      eq(m.classify("a \\" .. macro .. "{b} + \\unknown{c}", display), false)
    end
    for _, call in ipairs(calls) do
      eq(call.cmd, "utftex")
    end
  end)
end
check("supported command prefix is not blocked", function()
  local _, route = m.classify([[a \neq b + \unknown{c}]])
  eq(route, "latex2text")
end)
check("escaped backslash does not create a silent-drop command", function()
  calls = {}
  m.classify([[a \\ne b + \unknown{c}]])
  eq(calls[#calls].cmd, "latex2text")
end)
check("fraction denominator stays grouped", function()
  eq(rendered([[\frac{1}{1+GH}]]), "1/(1+GH)")
end)
check("fraction next to a product stays grouped", function()
  eq(rendered([[\frac{A}{2}t^2]]), "(A/2)t²")
end)
check("boxed sum keeps grouping under exponent", function()
  eq(rendered([[\boxed{x+y}^2]]), "(x+y)²")
end)
check("nested boxes and escaped braces", function()
  eq(m.preprocess([[\boxed{\boxed{a} + \{b\}}]]), [[((a) + \{b\})]])
end)
check("box command boundary and escaped backslash", function()
  eq(m.preprocess([[\boxedness{x} \\boxed{y}]]), [[\boxedness{x} \\boxed{y}]])
end)
check("malformed box and tag remain raw", function()
  eq(m.classify([[\boxed{a]]), false)
  eq(m.classify([[a \tag*{1}]]), false)
end)
check("tag keeps its complete Chinese label", function()
  eq(rendered([[a \tag{门1}]], true), "a (门1)")
end)
for _, arrow in ipairs({ "xrightarrow", "xleftarrow" }) do
  check(arrow .. " with either label stays raw in both layouts", function()
    for _, display in ipairs({ false, true }) do
      eq(m.classify("a \\" .. arrow .. "{\\ \\int\\ } b", display), false)
      eq(m.classify("a \\" .. arrow .. "[below]{above} b", display), false)
    end
  end)
end
check("ampersands outside environments and escaped separators untouched", function()
  eq(
    m.preprocess([[a&b \& \begin{bmatrix}a\&b&c\end{bmatrix} d&e]]),
    [[a&b \& \begin{bmatrix}a\&b & c\end{bmatrix} d&e]]
  )
end)
for _, env in ipairs({
  "matrix",
  "pmatrix",
  "Bmatrix",
  "vmatrix",
  "Vmatrix",
  "smallmatrix",
  "array",
  "cases",
  "aligned",
}) do
  check(env .. " pads real separators", function()
    local before = "\\begin{" .. env .. "}a&b\\end{" .. env .. "}"
    eq(m.preprocess(before), before:gsub("&", " & "))
  end)
end
check("nested environments and text groups preserve scope", function()
  eq(
    m.preprocess([[\begin{matrix}\text{a&b}&\begin{other}c&d\end{other}&\begin{matrix}e&f\end{matrix}\end{matrix}&g]]),
    [[\begin{matrix}\text{a&b} & \begin{other}c&d\end{other} & \begin{matrix}e & f\end{matrix}\end{matrix}&g]]
  )
end)
check("comment ampersands are not matrix separators", function()
  eq(m.preprocess("\\begin{matrix}a&b % & {\n\\end{matrix}"), "\\begin{matrix}a & b % & {\n\\end{matrix}")
end)
check("leading minus uses stdin", function()
  eq(rendered([[-a+b]]), "-a+b")
end)
check("classification caches successes, failures and layout changes", function()
  local fresh = dofile(path)
  calls = {}
  fresh.classify([[\frac{1}{1+GH}]])
  eq(#calls, 2)
  fresh.classify([[\frac{1}{1+GH}]])
  fresh.classify([[\frac{1}{1+GH}]], true)
  fresh.classify([[\frac{1}{1+GH}]], true)
  eq(#calls, 2)
  fresh.classify([[a \ne b + \unknown{c}]])
  local count = #calls
  fresh.classify([[a \ne b + \unknown{c}]])
  fresh.classify([[a \ne b + \unknown{c}]], true)
  eq(#calls, count)
end)
local get_text = vim.treesitter.get_node_text
vim.treesitter.get_node_text = function(root)
  return root.text
end
local buf = vim.api.nvim_create_buf(false, true)
local function root(text, row, col, end_row, end_col)
  return {
    text = text,
    range = function()
      return row, col, end_row, end_col
    end,
  }
end
check("display parse uses safe builtin conversion and lazy require is cached", function()
  roots = {}
  local text = "$$" .. boxed .. "$$"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  local out = m.parse({ buf = buf, root = root(text, 0, 0, 0, #text), last = true })
  contains(out[1].output, "≠")
  eq(builtin_loads, 1)
  eq(#roots, 1)
end)
check("unsafe display root never reaches builtin", function()
  roots = {}
  local text = [[$$a \ne b + \unknown{c}$$]]
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  eq(#m.parse({ buf = buf, root = root(text, 0, 0, 0, #text), last = true }), 0)
  eq(#roots, 0)
end)
check("rejected final root still flushes kept roots", function()
  roots = {}
  local a, b = "$a$", [[$a \xrightarrow{label} b$]]
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "text " .. a .. " and " .. b })
  eq(#m.parse({ buf = buf, root = root(a, 0, 5, 0, 8), last = false }), 0)
  m.parse({ buf = buf, root = root(b, 0, 13, 0, 13 + #b), last = true })
  eq(#roots, 1)
  eq(roots[1].last, true)
  eq(builtin_loads, 1)
end)
check("table fraction keeps width compensation", function()
  local text = [[$\frac{1}{1+GH}$]]
  local line = "| " .. text .. " |"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  local marks = m.parse({ buf = buf, root = root(text, 0, 2, 0, 2 + #text), last = true })
  eq(#marks, 2)
  eq(marks[1].opts.virt_text[1][1], "1/(1+GH)")
  eq(marks[2].start_col, #line - 1)
end)
vim.treesitter.get_node_text = get_text
vim.system = system
vim.api.nvim_buf_delete(buf, { force = true })
print(string.format("%d PASS, %d FAIL", passes, failures))
os.exit(failures == 0 and 0 or 1)
