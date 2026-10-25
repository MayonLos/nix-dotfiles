local M = {}

local function normalize(path)
	path = vim.fn.expand(path)
	return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function within(path, root)
	return path == root or path:sub(1, #root + 1) == root .. "/"
end

function M.roots()
	local roots = {}
	local seen = {}
	local function add(path)
		if not path or path == "" then
			return
		end
		local root = normalize(path)
		if not seen[root] then
			seen[root] = true
			roots[#roots + 1] = root
		end
	end

	add(vim.env.NVIM_CONFIG_DIR or vim.fn.stdpath("config"))
	local options = require("mayon.generated").nix_options or {}
	if options.flake and options.flake ~= "" then
		add(options.flake .. "/aspects/dev/neovim/config")
	end
	return roots
end

function M.root_for_path(path)
	if not path or path == "" then
		return nil
	end
	path = normalize(path)
	for _, root in ipairs(M.roots()) do
		if within(path, root) then
			return root
		end
	end
end

function M.is_config_path(path)
	return M.root_for_path(path) ~= nil
end

function M.is_config_root(path)
	if not path or path == "" then
		return false
	end
	path = normalize(path)
	for _, root in ipairs(M.roots()) do
		if path == root then
			return true
		end
	end
	return false
end

return M
