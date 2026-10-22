-- Text helpers for statusline/tabline providers. Neovim parses '%' in these
-- strings as statusline syntax, and byte lengths do not measure CJK text.
local M = {}

function M.truncate(value, width, ellipsis)
	value = tostring(value or ""):gsub("[\r\n\t]", " ")
	if not width or vim.fn.strwidth(value) <= width then
		return value
	end

	ellipsis = ellipsis == nil and "…" or ellipsis
	local ellipsis_width = vim.fn.strwidth(ellipsis)
	if width <= ellipsis_width then
		return width > 0 and "." or ""
	end

	local result = ""
	for index = 0, vim.fn.strchars(value) - 1 do
		local char = vim.fn.strcharpart(value, index, 1)
		if vim.fn.strwidth(result .. char .. ellipsis) > width then
			break
		end
		result = result .. char
	end
	return result .. ellipsis
end

function M.escape(value)
	return (tostring(value or ""):gsub("%%", "%%%%"))
end

-- Return safe display text for a Heirline provider, optionally clipped to the
-- requested display-cell width before escaping statusline directives.
function M.fit(value, width)
	return M.escape(M.truncate(value, width))
end

return M
