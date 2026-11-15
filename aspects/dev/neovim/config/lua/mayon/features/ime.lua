-- Fcitx5 follows the editing mode. Leaving Insert, Terminal or a search line
-- always returns to the English layout so Normal-mode keys are never composed.
-- Prose buffers remember whether Rime was active and restore it on re-entry;
-- code buffers stay English. Rime keeps its own 中/英 sub-mode across switches.
local M = {}
local api = vim.api

local PROSE = { markdown = true, text = true, gitcommit = true, typst = true, tex = true, codecompanion = true }

-- Overridable for tests. fcitx5-remote talks to the daemon over D-Bus in ~2 ms;
-- run it synchronously so keys typed right after <Esc> already reach Vim raw.
function M.remote(args)
	local cmd = { "fcitx5-remote" }
	vim.list_extend(cmd, args or {})
	local ok, result = pcall(function()
		return vim.system(cmd, { text = true }):wait(200)
	end)
	return ok and result.code == 0 and vim.trim(result.stdout or "") or nil
end

local function restores(buf)
	return vim.bo[buf].buftype == "terminal" or PROSE[vim.bo[buf].filetype] == true
end

local function leave(buf)
	local active = M.remote() == "2"
	if buf then
		vim.b[buf].mayon_ime_active = active
	end
	if active then
		M.remote({ "-c" })
	end
end

local function enter(buf)
	if restores(buf) and vim.b[buf].mayon_ime_active then
		M.remote({ "-o" })
	end
end

function M.setup()
	-- No daemon (SSH, TTY, headless checks): leave every mode change untouched.
	if vim.fn.executable("fcitx5-remote") == 0 or not (vim.env.WAYLAND_DISPLAY or vim.env.DISPLAY) then
		return
	end
	M.attach()
end

function M.attach()
	local group = api.nvim_create_augroup("MayonIme", { clear = true })
	api.nvim_create_autocmd({ "InsertLeave", "TermLeave" }, {
		group = group,
		callback = function(ev)
			leave(ev.buf)
		end,
	})
	api.nvim_create_autocmd({ "InsertEnter", "TermEnter" }, {
		group = group,
		callback = function(ev)
			enter(ev.buf)
		end,
	})
	-- Searches may be typed in Chinese; the Normal mode after them may not.
	api.nvim_create_autocmd("CmdlineLeave", {
		group = group,
		pattern = { "/", "?" },
		callback = function()
			leave(nil)
		end,
	})
end

return M
