-- Shared by the immutable Nix wrapper and the Home Manager XDG entry.
if vim.g.mayon_config_loaded then
	return
end

-- Resolve the Home Manager symlink as well as direct -u/development entries.
-- Keep one copy of the configuration queries in runtimepath.
local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.uv.fs_realpath(source) or source)
vim.opt.runtimepath:remove(vim.fn.stdpath("config"))
vim.opt.runtimepath:remove(vim.fn.stdpath("config") .. "/after")
vim.opt.runtimepath:remove(root)
vim.opt.runtimepath:remove(root .. "/after")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(root .. "/after")

require("mayon.core.options").setup()
vim.cmd.colorscheme("onedark-darker")
require("mayon.ui").setup()
require("mayon.editor").setup()
require("mayon.files").setup()
require("mayon.image").setup()
require("mayon.core.icons").setup()
require("mayon.plugins").setup()
require("mayon.ui.noice").setup()
require("mayon.lsp").setup()
require("mayon.features.sessions").setup()
require("mayon.features.urls").setup()
require("mayon.core.keymaps").setup()
require("mayon.core.autocmds").setup()
vim.cmd.packadd("matchit")
require("mayon.breadcrumbs").setup()
require("mayon.statusline").setup()
require("mayon.tabline").setup()
vim.g.mayon_config_loaded = true
