-- Task lists: Enter continues "- [ ] " items and ,x toggles checkboxes.
-- Lives under after/ because the runtime markdown ftplugin resets 'comments'.

local buf = vim.api.nvim_get_current_buf()

-- Longer leaders first so "- [ ]" wins over "-".
vim.bo[buf].comments = "b:- [ ],b:* [ ],fb:*,fb:-,fb:+,n:>"
vim.opt_local.formatoptions:append("r")
vim.opt_local.formatoptions:remove("o")

local function toggle_line(line)
	local indent, bullet, mark, rest = line:match("^(%s*)([-*+]) %[([ xX])%](.*)$")
	if not indent then
		indent, bullet, mark, rest = line:match("^(%s*)(%d+[.)]) %[([ xX])%](.*)$")
	end
	if indent then
		return ("%s%s [%s]%s"):format(indent, bullet, mark == " " and "x" or " ", rest)
	end
	indent, bullet, rest = line:match("^(%s*)([-*+]) (.*)$")
	if not indent then
		indent, bullet, rest = line:match("^(%s*)(%d+[.)]) (.*)$")
	end
	if indent then
		return ("%s%s [ ] %s"):format(indent, bullet, rest)
	end
	indent, rest = line:match("^(%s*)(.*)$")
	return ("%s- [ ] %s"):format(indent, rest)
end

local function toggle(first, last)
	local lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
	for i, line in ipairs(lines) do
		lines[i] = toggle_line(line)
	end
	vim.api.nvim_buf_set_lines(buf, first - 1, last, false, lines)
end

vim.keymap.set("n", "<localleader>x", function()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	toggle(row, row + vim.v.count1 - 1)
end, { buffer = buf, desc = "Toggle task checkbox" })

vim.keymap.set("x", "<localleader>x", function()
	local a, b = vim.fn.line("v"), vim.fn.line(".")
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
	toggle(math.min(a, b), math.max(a, b))
end, { buffer = buf, desc = "Toggle task checkboxes" })

-- img-clip saves the clipboard image to ./assets/ beside this file.
vim.keymap.set("n", "<localleader>p", function()
	vim.cmd.PasteImage()
end, { buffer = buf, desc = "Paste clipboard image" })

vim.b[buf].undo_ftplugin = (vim.b[buf].undo_ftplugin or "")
	.. "|setlocal comments< formatoptions<"
	.. "|silent! nunmap <buffer> <localleader>x|silent! xunmap <buffer> <localleader>x"
	.. "|silent! nunmap <buffer> <localleader>p"
