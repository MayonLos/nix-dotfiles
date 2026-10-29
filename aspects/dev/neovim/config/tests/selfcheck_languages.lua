local capture = assert(_G.MayonSelfcheck)
-- The package must work without channels, including nixd's initial workers.
vim.env.NIX_PATH = ""
capture.hook_notify()
vim.api.nvim_exec_autocmds("UIEnter", {})
vim.wait(100)
require("mayon.features.ai_completion").set("off")
local cases = {
	tsx = { "App.tsx", "typescriptreact", "ts_ls", { "export function App() { return <div>Fixture</div>; }" } },
	ts = {
		"main.ts",
		"typescript",
		"ts_ls",
		{ "export function square(value: number): number { return value * value; }" },
	},
	c = { "main.c", "c", "clangd", { "int square(int value) { return value * value; }" } },
	h = { "main.h", "cpp", "clangd", { "#pragma once", "int square(int value);" } },
	nix = { "default.nix", "nix", "nixd", { "let answer = 42; in answer" } },
	lua = { "main.lua", "lua", "lua_ls", { "local answer = 42", "return answer" } },
	md = { "README.md", "markdown", "marksman", { "# Fixture", "", "A local document." } },
	py = { "main.py", "python", "basedpyright", { "def square(value: int) -> int:", "    return value * value" } },
	json = { "data.json", "json", "jsonls", { '{ "answer": 42 }' } },
	yaml = { "data.yaml", "yaml", "yamlls", { "answer: 42" } },
	sh = { "main.sh", "sh", "bashls", { "#!/usr/bin/env bash", 'printf "%s\\n" fixture' } },
	make = { "Makefile", "make", false, { "all:", "\t@echo fixture" } },
	cmake = {
		"CMakeLists.txt",
		"cmake",
		"cmake",
		{ "cmake_minimum_required(VERSION 3.20)", "project(Fixture C)", "add_library(fixture main.c)" },
	},
}
local kind = assert(vim.env.NVIM_SAMPLE)
local case = assert(cases[kind])
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.git", "p")
vim.fn.writefile(
	{ '{"compilerOptions":{"jsx":"preserve","strict":true},"include":["**/*"]}' },
	root .. "/tsconfig.json"
)
vim.fn.writefile({ '{"name":"selfcheck","private":true}' }, root .. "/package.json")
vim.fn.writefile({ "declare namespace JSX { interface IntrinsicElements { div: unknown } }" }, root .. "/jsx.d.ts")
vim.fn.writefile({ "int square(int value) { return value * value; }" }, root .. "/main.c")
local path = root .. "/" .. case[1]
vim.fn.writefile(case[4], path)
vim.cmd.cd(root)
capture.phase = kind .. ": first file"
vim.cmd.edit(path)
assert(vim.bo.filetype == case[2], "wrong filetype " .. vim.bo.filetype)
local buf = vim.api.nvim_get_current_buf()
assert(vim.treesitter.highlighter.active[buf], "no parser/highlighter for " .. kind)
if case[3] then
	assert(
		vim.wait(30000, function()
			local client = vim.lsp.get_clients({ bufnr = buf, name = case[3] })[1]
			return client and client.initialized
		end, 50),
		"LSP did not attach: " .. case[3]
	)
	local client = vim.lsp.get_clients({ bufnr = buf, name = case[3] })[1]
	if client:supports_method("textDocument/hover") then
		if kind == "nix" then
			vim.api.nvim_win_set_cursor(0, { 1, 20 })
		end
		local response, err = client:request_sync(
			"textDocument/hover",
			vim.lsp.util.make_position_params(0, client.offset_encoding),
			10000,
			buf
		)
		assert(response and not response.err, vim.inspect(err or response))
	end
end
capture.phase = kind .. ": format/diagnostics"
local format_error
require("conform").format({ async = false, lsp_format = "fallback", timeout_ms = 10000 }, function(err)
	format_error = err
end)
assert(not format_error, vim.inspect(format_error))
vim.wait(500)
local ns = vim.api.nvim_create_namespace("selfcheck-diagnostics")
vim.diagnostic.set(
	ns,
	buf,
	{ { lnum = 0, col = 0, message = "offline fixture diagnostic", severity = vim.diagnostic.severity.WARN } }
)
vim.diagnostic.open_float({ bufnr = buf, scope = "buffer" })
vim.cmd.redraw()
assert(#capture.finish() == 0, "runtime error: " .. vim.inspect(capture.events))
print(kind .. ": parser, LSP (where configured), hover, formatter, diagnostics passed")
