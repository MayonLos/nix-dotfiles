local M = {}
local function esc(s)
	return s:gsub("%%", "%%%%")
end
function M.click(id)
	vim.schedule(function()
		if id == 1 then
			require("snacks").picker.projects()
		elseif id == 2 then
			require("snacks").picker.git_branches()
		elseif id == 3 then
			require("mayon.ui.search").open()
		elseif id == 4 then
			require("mayon.features.tasks").run_last()
		elseif id == 5 then
			require("mayon.features.tasks").pick()
		elseif id == 6 then
			require("mayon.ui.workspace").action("ai")
		elseif id == 7 then
			require("lz.n").trigger_load("which-key.nvim")
			require("which-key").show({ global = true })
		end
	end)
end
local function button(id, text, hl)
	return "%#" .. (hl or "MayonToolbar") .. "#%" .. id .. "@v:lua.MayonToolbarClick@" .. text .. "%X"
end
function M.render()
	local root = vim.fn.getcwd()
	local name = vim.fs.basename(root)
	local badge = ""
	for word in name:gmatch("[%w]+") do
		badge = badge .. word:sub(1, 1):upper()
	end
	badge = badge:sub(1, 2)
	local git = vim.b[require("mayon.ui.tabline").active_buffer() or 0].gitsigns_status_dict or {}
	local branch = git.head or vim.g.mayon_branch or ""
	local project = button(1, " " .. badge .. " " .. esc(name) .. " ⌄  ", "MayonProject")
	local branch_part = branch ~= "" and button(2, " " .. esc(branch) .. " ⌄ " .. (vim.g.mayon_ahead_behind or ""))
		or ""
	local task = package.loaded["mayon.features.tasks"] and require("mayon.features.tasks").cached_last() or nil
	local run = button(4, " ▶ " .. esc(task and task.title or "Run"), "MayonRun") .. button(5, " ⌄ ")
	return project
		.. branch_part
		.. "%="
		.. button(3, "   Search Everywhere  ␣␣ ", "MayonToolbarHint")
		.. "%="
		.. run
		.. button(6, " 󰚩 ")
		.. button(7, "  ")
		.. " "
end
function M.setup()
	require("mayon.features.tasks")
	_G.MayonToolbarClick = M.click
	vim.o.tabline = "%!v:lua.require'mayon.ui.toolbar'.render()"
	local function branch()
		vim.system(
			{ "git", "status", "--porcelain=v2", "--branch" },
			{ cwd = vim.fn.getcwd(), text = true },
			function(result)
				if result.code == 0 then
					local text = result.stdout or ""
					vim.g.mayon_branch = text:match("# branch.head ([^\n]+)") or ""
					local a, b = text:match("# branch.ab %+([0-9]+) %-([0-9]+)")
					vim.g.mayon_ahead_behind = a and ("↑" .. a .. " ↓" .. b) or ""
					vim.schedule(function()
						vim.cmd.redrawtabline()
					end)
				end
			end
		)
	end
	vim.api.nvim_create_autocmd({ "DirChanged", "FocusGained" }, { callback = branch })
	branch()
end
return M
