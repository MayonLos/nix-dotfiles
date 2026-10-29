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
	local devicons = require("nvim-web-devicons")
	-- Keep the established devicons, replacing their purple/pink accents with
	-- the editor's blue. Configure through the plugin API so theme reloads
	-- preserve the same foregrounds rather than rewriting highlights later.
	local overrides = {
		m = matlab,
		mlx = vim.tbl_extend("force", matlab, { name = "MatlabLiveScript" }),
		mat = vim.tbl_extend("force", matlab, { name = "MatlabData" }),
		slx = vim.tbl_extend("force", matlab, { name = "Simulink" }),
	}
	for name, icon in pairs(devicons.get_icons()) do
		local hex = icon.color and tonumber(icon.color:sub(2), 16)
		if hex then
			local r, g, b = math.floor(hex / 65536), math.floor(hex / 256) % 256, hex % 256
			if r > g * 1.12 and b > g * 1.1 then
				overrides[name] = vim.tbl_extend(
					"force",
					icon,
					{ color = require("mayon.generated").palette.blue, cterm_color = "75" }
				)
			end
		end
	end
	devicons.setup({ color_icons = true, override = overrides })
end

-- Dashboard icons do not need diagnostic state. Configure the gutter when the
-- language-service core starts, rather than loading vim.diagnostic on frame 1.
function M.diagnostics()
	vim.diagnostic.config({
		signs = {
			text = {
				[vim.diagnostic.severity.ERROR] = "●",
				[vim.diagnostic.severity.WARN] = "•",
				[vim.diagnostic.severity.INFO] = "·",
				[vim.diagnostic.severity.HINT] = "·",
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
