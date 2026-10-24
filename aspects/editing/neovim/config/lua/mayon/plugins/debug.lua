local function configure()
	vim.cmd.packadd("nvim-dap-view")
	vim.cmd.packadd("nvim-dap-virtual-text")
	local dap = require("dap")
	local generated = require("mayon.generated")
	local tools = generated.tools or {}
	local lldb_dap = assert(tools.lldb_dap, "Nix did not inject the lldb-dap executable")
	local debugpy_python = assert(tools.debugpy_python, "Nix did not inject the debugpy Python interpreter")

	dap.adapters.lldb = {
		type = "executable",
		command = lldb_dap,
		name = "lldb-dap",
	}
	dap.adapters.python = {
		type = "executable",
		command = debugpy_python,
		args = { "-m", "debugpy.adapter" },
	}

	local function executable_prompt()
		return vim.fn.input("Executable: ", vim.fn.getcwd() .. "/", "file")
	end
	local function project_python()
		local file_dir = vim.fn.expand("%:p:h")
		if file_dir == "" then
			file_dir = vim.fn.getcwd()
		end
		local venv = vim.fs.find(".venv", { upward = true, type = "directory", path = file_dir })[1]
		local local_python = venv and (venv .. "/bin/python")
		if local_python and vim.fn.executable(local_python) == 1 then
			return local_python
		end
		local active_python = vim.env.VIRTUAL_ENV and (vim.env.VIRTUAL_ENV .. "/bin/python")
		if active_python and vim.fn.executable(active_python) == 1 then
			return active_python
		end
		return vim.fn.exepath("python3") ~= "" and vim.fn.exepath("python3") or debugpy_python
	end
	local native = {
		{
			name = "Launch executable",
			type = "lldb",
			request = "launch",
			program = executable_prompt,
			cwd = "${workspaceFolder}",
			stopOnEntry = false,
			args = {},
		},
	}
	for _, ft in ipairs({ "c", "cpp", "rust" }) do
		dap.configurations[ft] = vim.deepcopy(native)
	end
	dap.configurations.python = {
		{
			name = "Launch current file",
			type = "python",
			request = "launch",
			program = "${file}",
			cwd = "${workspaceFolder}",
			pythonPath = project_python,
			console = "integratedTerminal",
			justMyCode = true,
		},
	}

	require("dap-view").setup({})
	require("nvim-dap-virtual-text").setup({
		virt_text_pos = "eol",
		all_references = false,
		virt_lines = false,
	})

	local function map(lhs, rhs, desc)
		vim.keymap.set("n", lhs, rhs, { desc = desc })
	end
	map("<F5>", dap.continue, "Debug: continue")
	map("<F10>", dap.step_over, "Debug: step over")
	map("<F11>", dap.step_into, "Debug: step into")
	map("<F12>", dap.step_out, "Debug: step out")
	map("<leader>db", dap.toggle_breakpoint, "Debug: toggle breakpoint")
	map("<leader>dB", function()
		dap.set_breakpoint(vim.fn.input("Breakpoint condition: "))
	end, "Debug: conditional breakpoint")
	map("<leader>dc", dap.continue, "Debug: continue")
	map("<leader>di", dap.step_into, "Debug: step into")
	map("<leader>do", dap.step_over, "Debug: step over")
	map("<leader>dO", dap.step_out, "Debug: step out")
	map("<leader>dr", dap.repl.toggle, "Debug: toggle REPL")
	map("<leader>dl", dap.run_last, "Debug: run last")
	map("<leader>dt", dap.terminate, "Debug: terminate")
	map("<leader>dv", function()
		require("dap-view").toggle()
	end, "Debug: toggle views")
end

return {
	{
		"nvim-dap",
		keys = {
			"<F5>",
			"<F10>",
			"<F11>",
			"<F12>",
			"<leader>db",
			"<leader>dB",
			"<leader>dc",
			"<leader>di",
			"<leader>do",
			"<leader>dO",
			"<leader>dr",
			"<leader>dl",
			"<leader>dt",
			"<leader>dv",
		},
		after = configure,
	},
}
