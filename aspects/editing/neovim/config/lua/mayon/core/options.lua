local M = {}

function M.setup()
	vim.g.mapleader = " "
	-- This config uses Lua plugins only; remote plugin hosts stay disabled.
	for _, provider in ipairs({ "python3", "ruby", "node", "perl" }) do
		vim.g["loaded_" .. provider .. "_provider"] = 0
	end
	local options = {
		clipboard = "unnamedplus",
		breakindent = true,
		breakindentopt = "shift:2,min:20",
		concealcursor = "nvic",
		conceallevel = 2,
		cursorline = true,
		expandtab = true,
		foldcolumn = "0",
		foldenable = true,
		foldlevel = 99,
		foldlevelstart = 99,
		ignorecase = true,
		laststatus = 3,
		list = true,
		listchars = { tab = "» ", trail = "·", nbsp = "␣" },
		number = true,
		relativenumber = true,
		scrolloff = 8,
		shiftwidth = 4,
		showmode = false,
		showbreak = "",
		sidescrolloff = 8,
		smoothscroll = true,
		linebreak = true,
		showtabline = 2,
		signcolumn = "yes",
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
	vim.opt.fillchars:append({ vert = " ", vertleft = " ", vertright = " ", verthoriz = " " })
	vim.filetype.add({ extension = { mdx = "markdown" } })
end

return M
