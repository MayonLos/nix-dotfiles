-- Run in the wrapped editor so Blink and its snippet provider are available.
local source_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:gsub("^@", ""), ":p")
local config_dir = vim.fs.dirname(vim.fs.dirname(source_path))

local config = require("blink.cmp.config")
local configured_path = config_dir .. "/snippets"
local snippet_opts = config.sources.providers.snippets.opts
assert(snippet_opts, "the startup config must configure Blink's snippets provider")
assert(vim.tbl_contains(snippet_opts.search_paths, configured_path), "startup must include this config's snippets")

-- Exercise Blink's real per-filetype provider registry and lazydev's module
-- completion implementation against a specific module prefix.
local previous_buf = vim.api.nvim_get_current_buf()
local lua_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, lua_buf)
vim.bo[lua_buf].filetype = "lua"
local sources = require("blink.cmp.sources.lib")
local enabled_sources = sources.get_enabled_provider_ids("default")
assert(vim.list_contains(enabled_sources, "lazydev"), "Lua buffers should enable lazydev completions")
local lazydev_provider = sources.get_provider_by_id("lazydev")
assert(lazydev_provider.name == "Lua Modules", "Blink should register the configured Lua module provider")
local lazydev_prefix = "require('blink.cmp."
vim.api.nvim_buf_set_lines(lua_buf, 0, -1, false, { lazydev_prefix })
local lazydev_response
lazydev_provider.module:get_completions({
	id = 74,
	cursor = { 1, #lazydev_prefix },
	bounds = { start_col = 1 },
	line = lazydev_prefix,
}, function(result)
	lazydev_response = result
end)
assert(lazydev_response and #lazydev_response.items > 0, "lazydev should return module completions")
local blink_config_item
for _, candidate in ipairs(lazydev_response.items) do
	if candidate.label == "blink.cmp.config" then
		blink_config_item = candidate
		break
	end
end
assert(blink_config_item, "lazydev should discover a real Blink module from the runtime path")
vim.api.nvim_win_set_buf(0, previous_buf)
vim.api.nvim_buf_delete(lua_buf, { force = true })

local provider = require("blink.cmp.sources.lib").get_provider_by_id("snippets")
local source = provider.module
local registry = source.registry
assert(vim.tbl_contains(registry.config.search_paths, configured_path), "Blink must scan the repo snippets")

local snippets = registry:get_snippets_for_ft("cpp")
local function find_snippet(prefix, body_pattern)
	for _, snippet in ipairs(snippets) do
		if snippet.prefix == prefix and table.concat(snippet.body, "\n"):find(body_pattern, 1, true) then
			return snippet
		end
	end
end

local cpt = find_snippet("cpt", "#include <bits/stdc++.h>")
assert(cpt, "the custom C++ cpt snippet must load from cpp.json")
local forr = find_snippet("forr", "for (int")
assert(forr, "the custom C++ forr snippet must load alongside bundled snippets")
local vt = find_snippet("vt", "vector<")
assert(vt, "the custom C++ vt snippet must load from cpp.json")

-- Ask Blink's real snippets provider for completion items, then expand and
-- advance one placeholder through Neovim's native snippet engine.
local prefix = "forr"
vim.lsp.enable("clangd", false)
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, buf)
vim.bo[buf].filetype = "cpp"
local response
source:get_completions({
	id = 73,
	cursor = { 1, #prefix },
	bounds = { start_col = 1 },
	get_line = function()
		return prefix
	end,
}, function(result)
	response = result
end)
assert(response and not response.is_incomplete_forward and not response.is_incomplete_backward)
local item
for _, candidate in ipairs(response.items) do
	if candidate.label == "forr" and candidate.insertText:find("for (int", 1, true) then
		item = candidate
		break
	end
end
assert(item, "Blink's provider must offer the custom forr completion")

vim.api.nvim_buf_set_lines(buf, 0, -1, false, { prefix })
vim.api.nvim_win_set_cursor(0, { 1, #prefix })
vim.api.nvim_buf_set_text(buf, 0, 0, 0, #prefix, {})
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.snippet.expand(item.insertText)
local expanded = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
assert(expanded[1]:find("for (int i = 0; i < n; i++) {", 1, true), "forr body must expand")
assert(vim.snippet.active(), "expanded snippet should expose native tabstops")
local first_stop = vim.api.nvim_win_get_cursor(0)
vim.snippet.jump(1)
local second_stop = vim.api.nvim_win_get_cursor(0)
assert(vim.snippet.active(), "jumping should keep the snippet session active")
assert(first_stop[1] ~= second_stop[1] or first_stop[2] ~= second_stop[2], "jump should advance the cursor")
vim.snippet.stop()
vim.api.nvim_win_set_buf(0, previous_buf)
vim.api.nvim_buf_delete(buf, { force = true })

io.stdout:write("Blink C++ snippets load, expand, and jump passed\n")
