local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(source))
vim.opt.rtp:prepend(root)

local original_generated = package.loaded["mayon.generated"]
package.loaded["mayon.generated"] = package.loaded["mayon.generated"] or { tools = {} }
local java_debug = require("mayon.features.java_debug")
local bundle_root = vim.fn.tempname()
vim.fn.mkdir(bundle_root, "p")
local debug_bundle = bundle_root .. "/com.microsoft.java.debug.plugin-fixture.jar"
local test_bundle = bundle_root .. "/com.microsoft.java.test.runner-fixture.jar"
local excluded_runner = bundle_root .. "/com.microsoft.java.test.runner-jar-with-dependencies.jar"
local excluded_coverage = bundle_root .. "/jacocoagent.jar"
for _, path in ipairs({ debug_bundle, test_bundle, excluded_runner, excluded_coverage }) do
	vim.fn.writefile({ "fixture" }, path)
end

local original_attach_calls = 0
local original_bundles = { bundle_root .. "/preexisting.jar" }
local java_buffer = vim.api.nvim_create_buf(false, true)
vim.bo[java_buffer].filetype = "java"
local config = java_debug.configure({
	init_options = { bundles = original_bundles, settings = { java = { format = { enabled = true } } } },
	on_attach = function(client, bufnr)
		original_attach_calls = original_attach_calls + 1
		assert(client.id == 57 and bufnr == java_buffer, "configure must forward the original on_attach arguments")
	end,
}, {
	bundles = {
		debug_bundle,
		test_bundle,
		debug_bundle,
		excluded_runner,
		excluded_coverage,
		bundle_root .. "/missing.jar",
	},
	is_file = function(path)
		return vim.fn.filereadable(path) == 1
	end,
})
assert(config.init_options.bundles[1] == original_bundles[1], "configure must retain existing bundles")
assert(vim.tbl_contains(config.init_options.bundles, debug_bundle), "java-debug bundle should be appended")
assert(vim.tbl_contains(config.init_options.bundles, test_bundle), "vscode-java-test bundle should be appended")
assert(vim.tbl_count(config.init_options.bundles) == 3, "duplicate, excluded, and missing jars should not be appended")
assert(config.init_options.settings.java.format.enabled, "configure must preserve other init options")

local original_loader = package.loaded["mayon.config.loader"]
local original_jdtls = package.loaded.jdtls
local original_jdtls_dap = package.loaded["jdtls.dap"]
local original_dap = package.loaded.dap
local original_debug = package.loaded["mayon.features.debug"]
local original_get_clients = vim.lsp.get_clients
local packed = {}
local dap_setup_calls = 0
local main_config_calls = 0
local test_class_calls = 0
local nearest_test_calls = 0
local provider_bufnr
local discovered_config = { name = "fixture Main", type = "java", request = "launch" }
local fake_dap = { listeners = { before = {} }, providers = { configs = {} }, configurations = { java = {} } }
package.loaded["mayon.config.loader"] = {
	pack = function(name)
		packed[#packed + 1] = name
	end,
}
package.loaded.jdtls = {
	setup_dap = function()
		dap_setup_calls = dap_setup_calls + 1
		if not fake_dap.providers.configs.jdtls then
			-- Matches the locked nvim-jdtls provider contract: it yields until
			-- asynchronous main-class discovery invokes its callback.
			fake_dap.providers.configs.jdtls = function(bufnr)
				provider_bufnr = bufnr
				local co = coroutine.running()
				vim.defer_fn(function()
					coroutine.resume(co, { discovered_config })
				end, 1)
				return coroutine.yield()
			end
		end
	end,
	test_class = function()
		test_class_calls = test_class_calls + 1
		return "class"
	end,
	test_nearest_method = function()
		nearest_test_calls = nearest_test_calls + 1
		return "nearest"
	end,
}
package.loaded["jdtls.dap"] = {
	setup_dap_main_class_configs = function()
		main_config_calls = main_config_calls + 1
		-- The locked upstream implementation clears its async provider here.
		fake_dap.providers.configs.jdtls = nil
	end,
}
package.loaded["mayon.generated"] = { tools = { java_debug_bundles = { debug_bundle, test_bundle } } }
vim.lsp.get_clients = function()
	error("Java DAP setup must not infer a buffer from the current window")
end

package.loaded.dap = nil
config.on_attach({ id = 57 }, java_buffer)
assert(original_attach_calls == 1, "original on_attach must run when DAP stays unloaded")
assert(#packed == 0, "opening a Java buffer must not load nvim-jdtls while DAP is unused")

package.loaded.dap = fake_dap
assert(java_debug.setup_dap(), "first lazy DAP setup should register Java support")
assert(dap_setup_calls == 1, "first lazy DAP setup should install the native provider")
assert(type(fake_dap.providers.configs.jdtls) == "function", "first setup must preserve native main-class provider")
assert(main_config_calls == 0, "setup must not replace the native async provider with a manual prefetch")
assert(vim.deep_equal(packed, { "nvim-jdtls" }), "nvim-jdtls must be lazy-packed on demand")

-- Model the user's first F5 immediately after DAP lazy-load: no earlier
-- manual main-class fetch has populated dap.configurations.java.
local configs
local scheduled_provider = {}
local original_defer_fn = vim.defer_fn
vim.defer_fn = function(callback)
	scheduled_provider[#scheduled_provider + 1] = callback
	return #scheduled_provider
end
local provider_co = coroutine.create(function()
	configs = fake_dap.providers.configs.jdtls(java_buffer)
end)
assert(coroutine.resume(provider_co), "first configuration provider call should start")
assert(coroutine.status(provider_co) == "suspended", "provider must wait for async discovery")
assert(#scheduled_provider == 1, "provider must start async main-class discovery")
scheduled_provider[1]()
vim.defer_fn = original_defer_fn
assert(coroutine.status(provider_co) == "dead", "native provider did not resume with discovered main classes")
assert(provider_bufnr == java_buffer, "F5 provider must receive the Java buffer, not the current buffer")
assert(configs and configs[1] == discovered_config, "first F5 must receive discovered Java main config")
assert(fake_dap.providers.configs.jdtls, "provider must remain installed after discovery")

-- An on_attach callback for a non-current Java buffer is also safe: setup is
-- global and does not run buffer-relative main-class discovery.
config.on_attach({ id = 57 }, java_buffer)
assert(original_attach_calls == 2, "original on_attach must remain callable after configuration")
assert(dap_setup_calls == 2 and main_config_calls == 0, "attach must preserve provider without eager prefetch")
assert(fake_dap.providers.configs.jdtls, "on_attach must leave the async provider installed")

local ensure_calls = 0
package.loaded["mayon.features.debug"] = {
	ensure = function()
		ensure_calls = ensure_calls + 1
		package.loaded.dap = fake_dap
	end,
}
assert(java_debug.test_class() == "class", "test_class should delegate to nvim-jdtls")
assert(java_debug.test_nearest_method() == "nearest", "test_nearest_method should delegate to nvim-jdtls")
assert(ensure_calls == 2 and test_class_calls == 1 and nearest_test_calls == 1)
assert(main_config_calls == 0 and fake_dap.providers.configs.jdtls, "test actions must not remove the F5 provider")

package.loaded["mayon.config.loader"] = original_loader
package.loaded.jdtls = original_jdtls
package.loaded["jdtls.dap"] = original_jdtls_dap
package.loaded.dap = original_dap
package.loaded["mayon.generated"] = original_generated
package.loaded["mayon.features.debug"] = original_debug
vim.lsp.get_clients = original_get_clients
vim.fn.delete(bundle_root, "rf")
print("Java debug bundles, first-F5 async provider, callback preservation, lazy loading, and test entries passed")
