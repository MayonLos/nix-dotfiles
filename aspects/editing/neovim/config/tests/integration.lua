-- Exercise the generated language contribution through the real Conform plugin.
vim.lsp.enable("lua_ls", false)
local path = vim.fn.tempname() .. ".lua"
vim.fn.writefile({ "local  answer=42", "return answer" }, path)
vim.cmd.edit(path)
assert(vim.bo.filetype == "lua")
assert(require("mayon.generated").languages.formatters.lua[1] == "stylua")
require("conform").format({ async = false, lsp_format = "never", timeout_ms = 10000 })
assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "local answer = 42", "StyLua did not format")
vim.cmd.bwipeout({ bang = true })
vim.fn.delete(path)
print("Generated language data reached the real StyLua formatter")
