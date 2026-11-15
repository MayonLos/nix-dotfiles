--!nonstrict
-- Pure geometry for the fullscreen drawer. All values are logical pixels: the
-- layer runtime renders with accessibility.ui_scale applied, so the drawer
-- divides the reported logical output size by that scale before calling here.
--
-- The page is laid out as a centered content column between the top edge and a
-- fixed Dock safe area. Rows are derived from the usable height, columns from
-- the usable width; everything is clamped so a narrow or short output still
-- yields a positive page size instead of dividing by zero.
local M = {}

local SAFE_BOTTOM = 104 -- Dock clearance kept free at the bottom of the page.
local CONTENT_MAX = 1180
local COLUMN_GAP = 16
local ROW_GAP = 14
local CELL_TARGET = 122
local CELL_MIN = 88
local ROW_MAX = 6
local COLUMN_MAX = 7
local COLUMN_MIN_CELL = 100
local CELL_WIDTH_MAX = 168
local CELL_WIDTH_MIN = 24
local ICON_MAX = 72
local ICON_MIN = 24
local SEARCH_HEIGHT = 44
local CHIPS_HEIGHT = 30
local DOTS_HEIGHT = 16
local GAP_SEARCH = 18
local GAP_CHIPS = 22
local GAP_DOTS = 18
local CHROME = SEARCH_HEIGHT + CHIPS_HEIGHT + DOTS_HEIGHT + GAP_SEARCH + GAP_CHIPS + GAP_DOTS
local CONTENT_PAD = 24

local function clamp(value, low, high)
	if value < low then
		return low
	end
	if value > high then
		return high
	end
	return value
end

function M.compute(width, height)
	width = math.max(64, tonumber(width) or 1280)
	height = math.max(64, tonumber(height) or 800)

	local side = clamp(math.floor(width * 0.075 + 0.5), 24, 96)
	local contentWidth = math.min(CONTENT_MAX, math.max(160, width - side * 2))
	contentWidth = math.min(contentWidth, width - 8)

	-- Start from the natural column count for the available width, then shrink
	-- only if the resulting cells would be too narrow to draw.
	local columns = clamp(math.floor((contentWidth + COLUMN_GAP) / (COLUMN_MIN_CELL + COLUMN_GAP)), 1, COLUMN_MAX)
	local cellWidth
	while true do
		cellWidth = math.floor((contentWidth - (columns - 1) * COLUMN_GAP) / columns)
		if cellWidth >= CELL_WIDTH_MIN or columns == 1 then
			break
		end
		columns = columns - 1
	end
	cellWidth = clamp(cellWidth, CELL_WIDTH_MIN, CELL_WIDTH_MAX)
	local gridWidth = columns * cellWidth + (columns - 1) * COLUMN_GAP

	local available = height - SAFE_BOTTOM - CONTENT_PAD * 2 - CHROME
	local rows = clamp(math.floor((available + ROW_GAP) / (CELL_TARGET + ROW_GAP)), 1, ROW_MAX)
	local cellHeight = math.floor((available - (rows - 1) * ROW_GAP) / rows)
	cellHeight = clamp(cellHeight, CELL_MIN, CELL_TARGET)
	if available < CELL_MIN then
		-- Very short output: one compact row is the most that can be shown.
		cellHeight = math.max(48, available)
	end
	local iconSize = clamp(math.min(cellHeight - 46, cellWidth - 24), ICON_MIN, ICON_MAX)
	local labelSize
	if cellWidth < 96 then
		labelSize = 10
	elseif cellWidth < 120 then
		labelSize = 11
	else
		labelSize = 12.5
	end
	local gridHeight = rows * cellHeight + (rows - 1) * ROW_GAP
	local searchWidth = clamp(math.floor(contentWidth * 0.4 + 0.5), 240, 460)
	if searchWidth > contentWidth then
		searchWidth = contentWidth
	end

	return {
		width = width,
		height = height,
		safeBottom = SAFE_BOTTOM,
		contentWidth = contentWidth,
		searchWidth = searchWidth,
		columns = columns,
		rows = rows,
		pageSize = math.max(1, columns * rows),
		cellWidth = cellWidth,
		cellHeight = cellHeight,
		cellRadius = math.min(18, math.floor(cellWidth / 7)),
		iconSize = iconSize,
		labelSize = labelSize,
		columnGap = COLUMN_GAP,
		rowGap = ROW_GAP,
		gridWidth = gridWidth,
		gridHeight = gridHeight,
	}
end

return M
