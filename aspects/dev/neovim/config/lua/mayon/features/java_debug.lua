local M = {}
local excluded_bundles = {
	["com.microsoft.java.test.runner-jar-with-dependencies.jar"] = true,
	["jacocoagent.jar"] = true,
}

local function bundle_paths(options)
	local opts = options or {}
	local generated = require("mayon.generated")
	local paths = opts.bundles or (generated.tools and generated.tools.java_debug_bundles)
	if not paths and generated.tools.java_debug_manifest then
		paths = dofile(generated.tools.java_debug_manifest)
	end
	paths = paths or {}
	if type(paths) ~= "table" then
		return {}
	end
	return paths
end

local function configured_bundles(config, paths, is_file)
	local init_options = config.init_options or {}
	local bundles = vim.deepcopy(init_options.bundles or {})
	local present = {}
	for _, path in ipairs(bundles) do
		present[path] = true
	end
	for _, path in ipairs(paths) do
		if type(path) == "string" and path:match("%.jar$") and not excluded_bundles[vim.fs.basename(path)] then
			local stat = vim.uv.fs_stat(path)
			local exists = is_file and is_file(path) or (stat and stat.type == "file")
			if exists and not present[path] then
				bundles[#bundles + 1] = path
				present[path] = true
			end
		end
	end
	config.init_options = init_options
	config.init_options.bundles = bundles
	return bundles
end

local function load_jdtls()
	require("mayon.config.loader").pack("nvim-jdtls")
	return require("jdtls")
end

local function setup_dap(bundles)
	local dap = package.loaded.dap
	if not dap then
		return false
	end
	if #bundles == 0 then
		return false
	end
	local jdtls = load_jdtls()
	jdtls.setup_dap()
	return true
end

function M.configure(config, options)
	config = config or {}
	local bundles = configured_bundles(config, bundle_paths(options), options and options.is_file)
	local on_attach = config.on_attach
	config.on_attach = function(client, bufnr)
		if on_attach then
			on_attach(client, bufnr)
		end
		-- Do not load the DAP feature just because a Java buffer was opened.
		if package.loaded.dap then
			setup_dap(bundles)
		end
	end
	return config
end

function M.setup_dap(options)
	return setup_dap(bundle_paths(options))
end

local function run_test(method)
	require("mayon.features.debug").ensure()
	if not M.setup_dap() then
		vim.notify("Java debug bundles or the DAP feature are unavailable", vim.log.levels.WARN, { title = "Java DAP" })
		return false
	end
	local jdtls = load_jdtls()
	local action = jdtls[method]
	if type(action) ~= "function" then
		vim.notify("nvim-jdtls does not provide " .. method, vim.log.levels.WARN, { title = "Java DAP" })
		return false
	end
	return action()
end

function M.test_class()
	return run_test("test_class")
end

function M.test_nearest_method()
	return run_test("test_nearest_method")
end

return M
