local M = {}

function M.setup()
	vim.g.mapleader = " "
	vim.g.maplocalleader = ","
	-- 0.12 ships both markdown.vim and markdown.lua. Their undo_ftplugin
	-- strings both unmap [[/]], leaving E31 on lz.n's FileType replay. Keep
	-- the native Lua heading navigation and suppress only the duplicate Vim maps.
	vim.g.no_markdown_maps = 1
	-- This config uses Lua plugins only; remote plugin hosts stay disabled.
	for _, provider in ipairs({ "python3", "ruby", "node", "perl" }) do
		vim.g["loaded_" .. provider .. "_provider"] = 0
	end
	local options = {
		clipboard = "unnamedplus",
		-- 0.12.4: nearest has no effect with fuzzy; retain fuzzy sorting.
		completeopt = "menuone,noselect,popup,fuzzy",
		completeitemalign = "kind,abbr,menu",
		-- Keep the block/beam/bar shapes aligned with the mode-color palette.
		guicursor = "n:block-Cursor,v-ve:block-Cursor,i-ci:ver25-Cursor,r-cr-o:hor20-Cursor,c:ver25-Cursor,sm:block-Cursor",
		pumborder = "none",
		pumwidth = 28,
		pummaxwidth = 60,
		pumheight = 8,
		wildoptions = "pum,fuzzy",
		breakindent = true,
		breakindentopt = "shift:2,min:20",
		concealcursor = "nvic",
		conceallevel = 2,
		cursorline = true,
		cursorlineopt = "both",
		expandtab = true,
		foldcolumn = "0",
		foldenable = true,
		foldlevel = 99,
		foldlevelstart = 99,
		ignorecase = true,
		laststatus = 3,
		-- Keep native Progress events for the statusline, without ui2 messages.
		messagesopt = "hit-enter,history:500,progress:",
		list = true,
		listchars = { tab = "  ", trail = "·", nbsp = "␣" },
		number = true,
		-- Absolute numbers match the preview and keep line references stable.
		relativenumber = false,
		scrolloff = 8,
		shiftwidth = 4,
		showmode = false,
		showbreak = "↳ ",
		sidescrolloff = 8,
		smoothscroll = true,
		linebreak = true,
		showtabline = 2,
		signcolumn = "yes:2",
		smartcase = true,
		smartindent = true,
		softtabstop = 4,
		splitbelow = true,
		splitright = true,
		swapfile = false,
		tabstop = 4,
		termguicolors = true,
		timeoutlen = 400,
		undofile = true,
		updatetime = 250,
		winborder = "rounded",
		-- The Nixvim baseline left `wrap` at Neovim's default (`true`). Keep
		-- long prose and Markdown lines visible instead of clipping them at the
		-- right edge; break at word boundaries without noisy continuation arrows.
		wrap = true,
	}
	for name, value in pairs(options) do
		vim.opt[name] = value
	end
	if vim.env.SSH_CONNECTION or vim.env.SSH_TTY then
		vim.g.clipboard = "osc52"
	elseif vim.env.WAYLAND_DISPLAY and vim.fn.executable("wl-copy") == 1 then
		vim.g.clipboard = {
			name = "Wayland",
			copy = { ["+"] = "wl-copy --type text/plain", ["*"] = "wl-copy --primary --type text/plain" },
			paste = { ["+"] = "wl-paste --no-newline", ["*"] = "wl-paste --primary --no-newline" },
			cache_enabled = 0,
		}
	end
	vim.opt.diffopt:remove("inline:char")
	vim.opt.diffopt:append("inline:word")
	vim.opt.fillchars:append({
		eob = " ",
		vert = "│",
		vertleft = "│",
		vertright = "│",
		verthoriz = "┼",
		horiz = "─",
		horizup = "┴",
		horizdown = "┬",
	})
	-- Register the extra extension before the first read/new-file detection.
	vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
		once = true,
		callback = function()
			vim.filetype.add({ extension = { mdx = "markdown" } })
		end,
	})
end

return M
