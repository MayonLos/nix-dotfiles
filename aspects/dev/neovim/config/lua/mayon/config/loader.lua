-- Nix owns the payloads and their complete dependency graph. lz.n owns triggers.
local M = {}
local loaded = {}
local refresh_pending = false
local function refresh_theme()
	if refresh_pending then
		return
	end
	refresh_pending = true
	vim.schedule(function()
		refresh_pending = false
		require("mayon.ui.theme").refresh()
	end)
end
function M.pack(name)
	if loaded[name] then
		return
	end
	loaded[name] = true
	for _, dependency in ipairs(require("mayon.generated").plugin_dependencies[name] or {}) do
		M.pack(dependency)
	end
	vim.cmd.packadd(name)
end
function M.setup()
	-- Nix already puts start/ payloads on runtimepath before VIMINIT. Their
	-- plugin scripts will run in the normal startup pass; avoid packadd rescans.
	for _, name in ipairs(require("mayon.generated").startup_plugins or {}) do
		loaded[name] = true
	end
	vim.g.lz_n = { load = M.pack }
	local specs = {}
	for _, domain in ipairs({
		"snacks",
		"completion",
		"languages",
		"lua",
		"treesitter",
		"editing",
		"formatting",
		"lint",
		"git",
		"navigation",
		"utility",
		"markdown",
		"ai",
		"decorations",
		"layout",
	}) do
		vim.list_extend(specs, require("mayon.plugins." .. domain))
	end
	-- Keep load errors visible to both interactive users and the test runner.
	for _, spec in ipairs(specs) do
		local after = spec.after
		if after then
			spec.after = function(...)
				local ok, err = pcall(after, ...)
				if not ok then
					vim.g.mayon_load_error = tostring(err)
					error(err)
				end
				refresh_theme()
			end
		end
	end
	-- One-shot spec normalization walks heterogeneous tables. Tracing this
	-- bootstrap can cost more than executing it; keep JIT for actual editing.
	local load_specs = require("lz.n").load
	local jit_enabled = jit.status()
	jit.off()
	local ok, err = pcall(load_specs, specs)
	if jit_enabled then
		jit.on()
	end
	if not ok then
		error(err)
	end
	vim.api.nvim_create_autocmd("UIEnter", {
		once = true,
		callback = function()
			vim.schedule(function()
				vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy", modeline = false })
			end)
		end,
	})
end
return M
