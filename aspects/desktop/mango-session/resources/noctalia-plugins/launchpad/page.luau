--!nonstrict
-- Pure pagination and selection arithmetic for the Launchpad grid.
-- Kept free of ui.*/noctalia.* so the Lua model tests can exercise it directly.
local M = {}

local function clamp(value, low, high)
	if value < low then
		return low
	end
	if value > high then
		return high
	end
	return value
end

-- Number of pages needed for total items. Never zero, so an empty result still
-- has a well-defined current page and the drawer does not special-case it.
function M.count(total, pageSize)
	if total <= 0 then
		return 1
	end
	return math.ceil(total / math.max(1, pageSize))
end

function M.clampPage(pageNumber, pages)
	return clamp(math.floor(pageNumber or 1), 1, math.max(1, pages or 1))
end

-- 1-based inclusive bounds of a page. Both are 0 for an empty result so callers
-- can skip the row loop instead of indexing nil.
function M.slice(pageNumber, pageSize, total)
	if total <= 0 then
		return 0, 0
	end
	local size = math.max(1, pageSize)
	local first = (M.clampPage(pageNumber, M.count(total, size)) - 1) * size + 1
	local last = first + size - 1
	if last > total then
		last = total
	end
	return first, last
end

function M.pageOf(index, pageSize)
	if index <= 0 then
		return 1
	end
	return math.floor((index - 1) / math.max(1, pageSize)) + 1
end

-- One keyboard step across the whole match list. 0 means "nothing selected";
-- the first step selects the first match for either direction.
function M.move(selected, delta, total)
	if total <= 0 then
		return 0
	end
	if selected <= 0 then
		return 1
	end
	return clamp(selected + delta, 1, total)
end

return M
