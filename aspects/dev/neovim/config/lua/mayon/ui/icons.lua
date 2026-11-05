local M = {}

local ready = false
function M.ensure()
	if ready then
		return
	end
	ready = true
	require("mayon.config.loader").pack("nvim-web-devicons")
	local matlab = {
		icon = "󰘨",
		color = require("mayon.generated").palette.orange,
		cterm_color = "173",
		name = "Matlab",
	}
	-- Keep devicons' own semantic colors; only named entries that need a
	-- palette accent are overridden. MATLAB has no upstream entry at all, and
	-- C/C++ headers use the editor blue instead of the upstream purple.
	local header = { icon = "", color = require("mayon.generated").palette.blue, cterm_color = "75", name = "H" }
	local overrides = {
		m = matlab,
		mlx = vim.tbl_extend("force", matlab, { name = "MatlabLiveScript" }),
		mat = vim.tbl_extend("force", matlab, { name = "MatlabData" }),
		slx = vim.tbl_extend("force", matlab, { name = "Simulink" }),
		h = header,
		hpp = vim.tbl_extend("force", header, { name = "Hpp" }),
	}
	local devicons = require("nvim-web-devicons")
	devicons.setup({ color_icons = true, override = overrides })
end

-- Dashboard icons do not need diagnostic state. Configure the gutter when the
-- language-service core starts, rather than loading vim.diagnostic on frame 1.
-- Each severity keeps a visually distinct glyph instead of relying on color.
function M.diagnostics()
	vim.diagnostic.config({
		signs = {
			text = {
				[vim.diagnostic.severity.ERROR] = "●",
				[vim.diagnostic.severity.WARN] = "▲",
				[vim.diagnostic.severity.INFO] = "◆",
				[vim.diagnostic.severity.HINT] = "○",
			},
		},
	})
end

-- Return the pinned devicon and its foreground group for a file path. Callers
-- decide when to invoke this so the icon table stays lazy until a UI needs it.
function M.get(path)
	if not path or path == "" then
		return "  ", "Normal"
	end
	M.ensure()
	local filename = vim.fn.fnamemodify(path, ":t")
	local icon, highlight = require("nvim-web-devicons").get_icon(filename, nil, { default = true })
	if not icon then
		return "  ", "Normal"
	end
	return icon .. " ", highlight or "Normal"
end

M.setup = M.ensure
return M
