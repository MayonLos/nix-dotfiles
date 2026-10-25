-- Neovim 0.12.6's JavaFileTypeCleanUp unconditionally clears these groups,
-- even when SpotBugs was never configured. `silent!` still leaves E216 in
-- v:errmsg. Keep the groups present without enabling any SpotBugs actions.
vim.api.nvim_create_augroup("java_spotbugs", { clear = false })
vim.api.nvim_create_augroup("java_spotbugs_post", { clear = false })
