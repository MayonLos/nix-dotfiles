-- Document identity is preserved while a picker or tool window has focus.
local M = {}
local active_documents = {}

local excluded_filetypes = {
	checkhealth = true,
	["grug-far"] = true,
	grug_far = true,
	oil = true,
	aerial = true,
	trouble = true,
	quickfix = true,
	qf = true,
	help = true,
	man = true,
	helpft = true,
}

local function is_document(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].buflisted then
		return false
	end
	local buftype = vim.bo[buf].buftype
	if buftype ~= "" and buftype ~= "acwrite" then
		return false
	end
	local filetype = vim.bo[buf].filetype:lower()
	if excluded_filetypes[filetype] then
		return false
	end
	for _, prefix in ipairs({ "neogit", "snacks", "codecompanion", "claudecode" }) do
		if filetype:sub(1, #prefix) == prefix then
			return false
		end
	end
	return true
end
M.is_document = is_document

local function empty_placeholder(buf)
	if vim.api.nvim_buf_get_name(buf) ~= "" or vim.bo[buf].buftype ~= "" or vim.bo[buf].modified then
		return false
	end
	return not vim.api.nvim_buf_is_loaded(buf)
		or (vim.api.nvim_buf_line_count(buf) == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "")
end

-- Focus may move to a sidebar or prompt without changing the active document.
function M.active_buffer()
	local tab, buf = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_buf()
	if is_document(buf) and not empty_placeholder(buf) then
		active_documents[tab] = buf
	elseif not is_document(active_documents[tab]) or empty_placeholder(active_documents[tab]) then
		active_documents[tab] = nil
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
			local visible = vim.api.nvim_win_get_buf(win)
			if is_document(visible) and not empty_placeholder(visible) then
				active_documents[tab] = visible
				break
			end
		end
	end
	return active_documents[tab]
end

-- Presentation filtering never deletes a buffer or hides unsaved scratch work.
function M.buffers()
	local result = {}
	for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
		local buf = info.bufnr
		local empty = empty_placeholder(buf)
		if is_document(buf) and not empty then
			result[#result + 1] = buf
		end
	end
	return result
end

function M.select(buf)
	if not is_document(buf) then
		return
	end
	local function document_window(win)
		return vim.api.nvim_win_get_config(win).relative == "" and is_document(vim.api.nvim_win_get_buf(win))
	end
	local win = vim.api.nvim_get_current_win()
	if not document_window(win) then
		win = nil
		for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if document_window(candidate) then
				win = candidate
				break
			end
		end
		if not win then
			vim.cmd("botright vnew")
			win = vim.api.nvim_get_current_win()
		end
	end
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_set_current_win(win)
end

local ready, suspended = false, false
local roots = {}

function M.project(buf)
	local path = vim.api.nvim_buf_get_name(buf)
	local cwd = vim.fn.getcwd()
	local key = path .. "\0" .. cwd
	if not roots[key] then
		roots[key] = vim.fs.root(
			path ~= "" and path or cwd,
			{ { ".git", "flake.nix", "package.json", "Cargo.toml", "pyproject.toml" } }
		) or (path ~= "" and not vim.fs.relpath(cwd, path) and vim.fs.dirname(path)) or cwd
	end
	return roots[key]
end

function M.render()
	local buf = M.active_buffer()
	if not buf then
		return ""
	end
	local text = require("mayon.ui.text")
	local width = vim.o.columns
	local root = M.project(buf)
	local project = vim.fs.basename(root) or root
	local name = vim.api.nvim_buf_get_name(buf)
	local file = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]"
	local branch = vim.b[buf].gitsigns_head or (vim.b[buf].gitsigns_status_dict or {}).head or ""
	local side = math.max(4, math.floor(width * 0.25) - 3)
	local left = text.fit(project, side)
	local right = branch ~= "" and text.fit(" " .. branch, side) or ""
	local middle = text.fit(file, math.max(6, width - 2 * side - 8))
	local modified = vim.bo[buf].modified and "%#MayonModified# ●" or ""
	return "%#MayonHeaderMuted#  "
		.. left
		.. "%=%#MayonHeaderFile#"
		.. middle
		.. modified
		.. "%#MayonHeaderMuted#%="
		.. right
		.. "  "
end

function M.refresh()
	if not ready then
		return
	end
	local buf = vim.api.nvim_get_current_buf()
	local active = M.active_buffer()
	local visible = not suspended and vim.bo[buf].filetype ~= "snacks_dashboard" and active ~= nil
	if visible then
		visible = vim.tbl_contains(M.buffers(), active)
	end
	vim.o.showtabline = visible and 2 or 0
	vim.cmd.redrawtabline()
end

function M.suspend(value)
	suspended = value
	M.refresh()
end

function M.setup()
	if ready then
		return
	end
	ready = true
	vim.o.tabline = "%!v:lua.require'mayon.ui.tabline'.render()"
	local group = vim.api.nvim_create_augroup("MayonDocumentHeader", { clear = true })
	vim.api.nvim_create_autocmd(
		{ "BufEnter", "BufWinEnter", "WinEnter", "TabEnter", "BufFilePost", "BufModifiedSet", "UIEnter" },
		{
			group = group,
			callback = function()
				vim.schedule(M.refresh)
			end,
		}
	)
	vim.api.nvim_create_autocmd("DirChanged", {
		group = group,
		callback = function()
			roots = {}
			vim.schedule(M.refresh)
		end,
	})
	vim.api.nvim_create_autocmd("User", { group = group, pattern = "GitSignsUpdate", callback = M.refresh })
	vim.api.nvim_create_autocmd("TabClosed", {
		group = group,
		callback = function()
			for tab in pairs(active_documents) do
				if not vim.api.nvim_tabpage_is_valid(tab) then
					active_documents[tab] = nil
				end
			end
		end,
	})
	M.refresh()
end

return M
