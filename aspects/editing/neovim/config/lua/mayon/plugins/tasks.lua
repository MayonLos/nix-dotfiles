local function configure()
	local overseer = require("overseer")
	overseer.setup({
		task_list = { direction = "bottom", min_height = 10, max_height = 16 },
	})

	local function cmake_root(opts)
		return vim.fs.find("CMakeLists.txt", { upward = true, type = "file", path = opts.dir })[1]
	end
	overseer.register_template({
		name = "mayon-cmake",
		cache_key = cmake_root,
		generator = function(opts)
			local list = cmake_root(opts)
			if not list then
				return {}
			end
			local root = vim.fs.dirname(list)
			local function task(name, args, tags)
				return {
					name = name,
					desc = "CMake project task",
					tags = tags,
					builder = function()
						return { cmd = vim.list_extend({ "cmake" }, vim.deepcopy(args)), cwd = root }
					end,
				}
			end
			return {
				task("cmake configure", { "-S", ".", "-B", "build" }, { "BUILD" }),
				task("cmake build", { "--build", "build" }, { "BUILD" }),
				{
					name = "cmake test",
					desc = "Run CMake project tests",
					tags = { "TEST" },
					builder = function()
						return {
							cmd = { "ctest", "--test-dir", "build", "--output-on-failure" },
							cwd = root,
						}
					end,
				},
			}
		end,
	})

	vim.keymap.set("n", "<leader>rr", "<cmd>OverseerRun<cr>", { desc = "Run project task" })
	vim.keymap.set("n", "<leader>rt", "<cmd>OverseerToggle<cr>", { desc = "Toggle task list" })
	vim.keymap.set("n", "<leader>ra", "<cmd>OverseerTaskAction<cr>", { desc = "Task actions" })
	vim.keymap.set("n", "<leader>rc", function()
		overseer.run_template({ name = "cmake build" })
	end, { desc = "Run CMake build" })
end

return {
	{
		"overseer.nvim",
		cmd = {
			"OverseerOpen",
			"OverseerClose",
			"OverseerToggle",
			"OverseerRun",
			"OverseerShell",
			"OverseerTaskAction",
		},
		keys = { "<leader>rr", "<leader>rt", "<leader>ra", "<leader>rc" },
		after = configure,
	},
}
