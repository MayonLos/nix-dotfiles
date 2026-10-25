-- Color the terminal's padding and partial cells like Normal, including tmux.
-- nvim_ui_send reaches the TUI even when Neovim runs as an RPC server.
local M = {}

function M.sequence(content, tmux)
	if tmux then
		return "\27Ptmux;" .. content:gsub("\27", "\27\27") .. "\27\\"
	end
	return content
end

function M.setup()
	local active, original, waiting = false, nil, false
	local group = vim.api.nvim_create_augroup("MayonTerminalBackground", { clear = true })
	local function has_tui()
		for _, ui in ipairs(vim.api.nvim_list_uis()) do
			if ui.stdout_tty then
				return true
			end
		end
		return false
	end
	local function send(content)
		vim.api.nvim_ui_send(M.sequence(content, vim.env.TMUX ~= nil))
	end
	local function sync()
		if not active then
			return
		end
		local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
		if bg then
			send(string.format("\27]11;#%06x\27\\", bg))
		end
	end
	local function restore()
		if active then
			send(original and ("\27]11;" .. original .. "\27\\") or "\27]111\27\\")
		end
		active, waiting = false, false
	end
	vim.api.nvim_create_autocmd("TermResponse", {
		group = group,
		callback = function(ev)
			local sequence = ev.data and ev.data.sequence or ""
			local color = sequence:match("\27%]11;(rgb:%x+/%x+/%x+)")
			if waiting and color then
				original, waiting = color, false
				sync()
			end
		end,
	})
	vim.api.nvim_create_autocmd("UIEnter", {
		group = group,
		callback = function()
			if not has_tui() then
				return
			end
			active, waiting = true, true
			-- Preserve an existing dynamic shell background, not just Kitty's default.
			-- Query tmux itself: it routes the response back to this pane. A query
			-- passed straight to the outer terminal can have its reply consumed
			-- by tmux's own terminal parser instead of reaching Neovim.
			vim.api.nvim_ui_send("\27]11;?\27\\")
			vim.defer_fn(function()
				if waiting then
					-- A slow tmux/remote reply can still supply the original color
					-- after this fallback has painted the first frame.
					sync()
				end
			end, 120)
		end,
	})
	vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = sync })
	vim.api.nvim_create_autocmd({ "VimLeavePre", "VimSuspend" }, { group = group, callback = restore })
	vim.api.nvim_create_autocmd("VimResume", {
		group = group,
		callback = function()
			active = has_tui()
			sync()
		end,
	})
end

return M
