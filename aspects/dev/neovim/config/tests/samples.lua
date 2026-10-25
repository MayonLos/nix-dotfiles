-- Each invocation begins with an untouched startup and opens its first file.
local cases = {
	lua = { "main.lua", "lua_ls", { "local  answer=42", "return answer" } },
	cpp = { "main.cpp", "clangd", { "int answer(){return 42;}", "int main(){return answer();}" } },
	python = { "main.py", "basedpyright", { "import sys", "import os", "print(sys.version, os.name)" } },
	tex = { "note.tex", "texlab", { "\\documentclass{article}", "\\begin{document}", "$x^2$", "\\end{document}" } },
	rust = { "main.rs", "rust_analyzer", { 'fn main() { println!("ok"); }' } },
	go = { "main.go", "gopls", { "package main", "func main() {}" } },
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
if kind == "rust" or kind == "go" then
	local executable = kind == "rust" and "rust-analyzer" or "gopls"
	if vim.fn.executable(executable) ~= 1 then
		print(kind .. ": Tree-sitter parser passed; optional LSP absent from PATH, skipped")
		return
	end
end
assert(
	vim.wait(25000, function()
		local client = vim.lsp.get_clients({ bufnr = buf, name = case[2] })[1]
		return client and client.initialized
	end, 50),
	"LSP did not attach: " .. case[2]
)
local client = vim.lsp.get_clients({ bufnr = buf, name = case[2] })[1]
if kind == "python" then
	assert(
		vim.wait(25000, function()
			return #vim.lsp.get_clients({ bufnr = buf, name = "ruff" }) > 0
		end, 50),
		"Ruff LSP should attach alongside basedpyright"
	)
	local ruff = vim.lsp.get_clients({ bufnr = buf, name = "ruff" })[1]
	assert(ruff and ruff:supports_method("textDocument/codeAction"), "Ruff should expose code actions")
	local lines = vim.api.nvim_buf_line_count(buf)
	local response = ruff:request_sync("textDocument/codeAction", {
		textDocument = vim.lsp.util.make_text_document_params(buf),
		range = { start = { line = 0, character = 0 }, ["end"] = { line = lines, character = 0 } },
		context = { diagnostics = {}, only = { "source.organizeImports" } },
	}, 10000, buf)
	assert(response and response.result, "Ruff organize-imports request failed")
	local organize = vim.tbl_filter(function(action)
		return action.kind and action.kind:find("source.organizeImports", 1, true)
			or (action.title and action.title:lower():find("organize imports", 1, true))
	end, response.result)
	assert(#organize > 0, "Ruff did not return an organize-imports action")
	local action = organize[1]
	if not action.edit and not action.command then
		local resolved = ruff:request_sync("codeAction/resolve", action, 10000, buf)
		assert(resolved and resolved.result, "Ruff code action resolve request failed")
		action = resolved.result
	end
	if action.edit then
		vim.lsp.util.apply_workspace_edit(action.edit, ruff.offset_encoding)
	elseif action.command then
		local command = type(action.command) == "table" and action.command or action
		local ok, err = ruff:exec_cmd(command, { bufnr = buf })
		assert(ok ~= false, err or "Ruff organize-imports command failed")
	else
		assert(false, "Ruff organize-imports action had neither an edit nor command")
	end
	assert(
		vim.wait(3000, function()
			return vim.api.nvim_buf_get_lines(buf, 0, 2, false)[1] == "import os"
		end, 25),
		"Ruff organize-imports action did not sort imports"
	)
end
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
if kind == "tex" then
	assert(vim.treesitter.highlighter.active[buf], "LaTeX Tree-sitter highlighting did not start")
	assert(vim.lsp.config.texlab.settings.texlab.build.args[3] == "-synctex=1")
end
assert(not vim.g.mayon_load_error, vim.g.mayon_load_error)
assert(vim.v.errmsg == "", vim.v.errmsg)
print(kind .. ": first-file treesitter, " .. case[2] .. ", formatting and diagnostics loaded")
