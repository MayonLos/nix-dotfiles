-- Each invocation begins with an untouched startup and opens its first file.
local cases = {
	lua = { "main.lua", "lua_ls", { "local  answer=42", "return answer" } },
	cpp = { "main.cpp", "clangd", { "int answer(){return 42;}", "int main(){return answer();}" } },
	python = { "main.py", "basedpyright", { "value=1", "print(value)" } },
	toml = { "pyproject.toml", "taplo", { "[project]", 'name="sample"' } },
	markdown = { "README.md", "marksman", { "# Fixture", "", "A document." } },
	nix = { "default.nix", "nixd", { "{ a=1; }" } },
}
local kind = assert(vim.env.NVIM_SAMPLE)
local case = assert(cases[kind])
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.git", "p")
local file = root .. "/" .. case[1]
vim.fn.writefile(case[3], file)
vim.cmd.edit(file)
assert(vim.bo.filetype == kind)
local buf = vim.api.nvim_get_current_buf()
assert(vim.treesitter.highlighter.active[buf], "first buffer did not start treesitter: " .. kind)
assert(vim.bo.indentexpr:find("nvim-treesitter", 1, true), "first buffer did not get indentexpr")
assert(
	vim.wait(25000, function()
		local client = vim.lsp.get_clients({ bufnr = buf, name = case[2] })[1]
		return client and client.initialized
	end, 50),
	"LSP did not attach: " .. case[2]
)
local client = vim.lsp.get_clients({ bufnr = buf, name = case[2] })[1]
assert(package.loaded["lint"] and package.loaded["conform"])
local conform = require("conform")
local format_error
conform.format({ async = false, lsp_format = "never", timeout_ms = 10000 }, function(err)
	format_error = err
end)
assert(not format_error, format_error)
vim.wait(250)
if client:supports_method("textDocument/foldingRange") then
	assert(vim.wo.foldexpr == "v:lua.vim.lsp.foldexpr()", "folding did not prefer LSP")
end
if client:supports_method("textDocument/documentSymbol") then
	assert(vim.b.navic_client_id == client.id, "first LSP client missed Navic attach")
end
assert(not vim.g.mayon_load_error, vim.g.mayon_load_error)
assert(vim.v.errmsg == "", vim.v.errmsg)
print(kind .. ": first-file treesitter, " .. case[2] .. ", formatting and diagnostics loaded")
