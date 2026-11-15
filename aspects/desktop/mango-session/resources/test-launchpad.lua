-- Model, pagination, geometry and cache lifecycle tests.
-- Usage: lua test-launchpad.lua <generated plugin directory containing pinyin-data.luau>
-- Actual input dispatch, native visibility and app launching are headless checks.
local root = arg[1]
local modules = {}
require = function(path)
	if not modules[path] then
		modules[path] = dofile(root .. "/" .. string.sub(path, 3))
	end
	return modules[path]
end
local readings = require("./pinyin-data.luau")
assert(readings[12295] == "ling/xing/yuan") -- first stored codepoint (U+3007)
assert(readings[13312] == "qiu") -- cross-page lookup (U+3400)
assert(readings[19968] == "yi") -- cross-page CJK lookup (U+4E00)
assert(readings[20048] == "le/yue") -- preserve both heteronyms (U+4E50)
assert(readings[20108] == "er") -- same-page lookup (U+4E8C)
assert(readings[40869] == "yu") -- a later CJK page (U+9FA5)
assert(readings[205705] == "mo") -- last stored codepoint
assert(readings[19968] == "yi") -- cache hits preserve values
assert(readings[0] == nil and readings[1] == nil and readings[false] == nil)
local model = dofile(root .. "/model.luau")
local icons = model.iconOverrides({ "NVIM.desktop=/icons/nvim.png", "terminal=clock", "broken", "empty=" })
assert(icons.nvim == "/icons/nvim.png" and icons.terminal == "clock" and icons.broken == nil and icons.empty == nil)
local apps = {
	{ id = "code", name = "编辑器", search = "编辑器 code visual studio code", categories = "Development;IDE;" },
	{ id = "firefox", name = "Firefox", search = "firefox web browser", categories = "Network;WebBrowser;" },
	{ id = "calc", name = "计算器", search = "计算器 calc calculator", categories = "Utility;" },
}
assert(#model.filter(apps, "", "all") == 3)
assert(model.filter(apps, "Code", "all")[1].id == "code")
assert(model.filter(apps, "编辑", "all")[1].id == "code")
assert(model.filter(apps, "visual studio", "dev")[1].id == "code")
assert(#model.filter(apps, "firefox", "dev") == 0)
assert(#model.filter(apps, "missing", "all") == 0)
assert(#model.filter(apps, "", "all", { code = true }) == 2)
assert(model.filter(apps, "code", "all", { code = true })[1].id == "code")
assert(#model.categories(apps) == 4)
assert(model.categories(apps)[4].id == "system")
local categories = model.list()
assert(#categories == 8)
assert(categories[1].id == "all" and categories[1].label == "全部")
assert(categories[2].id == "dev" and categories[2].label == "开发")
assert(categories[8].id == "system" and categories[8].label == "系统")

-- Pagination and selection arithmetic stay correct at the edges: empty lists,
-- exact page boundaries, clamping and cross-page keyboard movement.
local pager = dofile(root .. "/page.luau")
assert(pager.count(0, 35) == 1)
assert(pager.count(1, 35) == 1 and pager.count(35, 35) == 1 and pager.count(36, 35) == 2)
assert(pager.count(70, 0) == 70)
assert(pager.clampPage(0, 3) == 1 and pager.clampPage(9, 3) == 3 and pager.clampPage(2, 0) == 1)
local first, last = pager.slice(1, 35, 40)
assert(first == 1 and last == 35)
first, last = pager.slice(2, 35, 40)
assert(first == 36 and last == 40)
first, last = pager.slice(3, 35, 40)
assert(first == 36 and last == 40) -- out-of-range page clamps to the last page
first, last = pager.slice(1, 35, 0)
assert(first == 0 and last == 0)
assert(pager.pageOf(0, 35) == 1 and pager.pageOf(1, 35) == 1 and pager.pageOf(35, 35) == 1)
assert(pager.pageOf(36, 35) == 2 and pager.pageOf(70, 35) == 2)
assert(pager.move(0, 1, 3) == 1 and pager.move(0, -1, 3) == 1)
assert(pager.move(3, 1, 3) == 3 and pager.move(1, -1, 3) == 1)
assert(pager.move(5, 7, 12) == 12 and pager.move(12, -7, 12) == 5)
assert(pager.move(0, 1, 0) == 0)

-- Geometry: one 7x5 page at 2560x1600@1.5 logical size, sane pages on narrow
-- and short outputs, and no zero/negative values on absurd ones.
local layout = dofile(root .. "/layout.luau")
local big = layout.compute(1707, 1067)
assert(big.columns == 7 and big.rows == 5 and big.pageSize == 35)
assert(big.safeBottom == 104)
assert(big.cellWidth <= 168 and big.cellWidth >= 24)
assert(big.gridWidth <= big.contentWidth and big.contentWidth <= big.width)
assert(big.iconSize >= 24 and big.iconSize <= big.cellWidth)
assert(big.searchWidth <= big.contentWidth and big.searchWidth >= 240)
assert(big.gridHeight == big.rows * big.cellHeight + (big.rows - 1) * big.rowGap)
local narrow = layout.compute(640, 480)
assert(narrow.columns >= 1 and narrow.rows == 1 and narrow.pageSize == narrow.columns)
assert(narrow.gridWidth <= narrow.contentWidth and narrow.cellWidth >= 24)
local tall = layout.compute(400, 900)
assert(tall.rows >= 1 and tall.columns >= 1 and tall.pageSize == tall.columns * tall.rows)
local short = layout.compute(1280, 300)
assert(short.rows == 1 and short.pageSize == short.columns)
for _, value in ipairs({
	short.columns,
	short.rows,
	short.pageSize,
	short.cellWidth,
	short.cellHeight,
	short.iconSize,
	short.gridWidth,
	short.gridHeight,
	short.searchWidth,
}) do
	assert(type(value) == "number" and value >= 1, tostring(value))
end
local tiny = layout.compute(200, 150)
for _, value in ipairs({ tiny.columns, tiny.rows, tiny.pageSize, tiny.cellWidth, tiny.gridWidth }) do
	assert(type(value) == "number" and value >= 1, tostring(value))
end
for _, height in ipairs({ 480, 600, 800, 1067, 1440 }) do
	local geometry = layout.compute(1707, height)
	assert(geometry.pageSize == geometry.columns * geometry.rows)
	assert(geometry.gridHeight + 148 + 2 * 24 + 104 <= height, "content must fit " .. height)
end

local chinese = {}
for i, name in ipairs({
	"腾讯会议",
	"微信",
	"音量控制",
	"Thunar 文件管理器",
	"重新启动",
	"银行",
	"行走",
	"Other 微信",
}) do
	chinese[i] = { id = tostring(i), name = name, search = string.lower(name), categories = "Utility;" }
end
table.insert(
	chinese,
	1,
	{ id = "file-roller", name = "文件压缩器", search = "文件压缩器 afaylu roller", categories = "Utility;" }
)
for query, expected in pairs({
	wx = "微信",
	weixin = "微信",
	txhy = "腾讯会议",
	yl = "音量控制",
	wjgl = "Thunar 文件管理器",
	chongxin = "重新启动",
	thunarwenjian = "Thunar 文件管理器",
	yinhang = "银行",
	xingzou = "行走",
}) do
	assert(model.filter(chinese, query, "all")[1].name == expected, query)
end
-- Same-tier candidates retain incoming usage order; direct names outrank initials,
-- which outrank full-pinyin substrings even when the latter arrived first.
local ranked = {}
for i, name in ipairs({ "二系", "日心", "RX tools", "日新", "Other 日新" }) do
	ranked[i] = { id = tostring(i), name = name, search = string.lower(name), categories = "Utility;" }
end
local matches = model.filter(ranked, "rx", "all")
assert(
	matches[1].name == "RX tools"
		and matches[2].name == "日心"
		and matches[3].name == "日新"
		and matches[4].name == "Other 日新"
		and matches[5].name == "二系"
)
assert(model.filter(chinese, "", "all")[1] == chinese[1])
local values, watchers, pending, shows, hides, launched = {}, {}, nil, 0, 0, {}
noctalia = {
	getConfig = function(key)
		if key == "icon_overrides" then
			return { "code=/icons/code-custom.png", "firefox=missing-override" }
		end
		if key == "hidden_apps" then
			return { "drawer-hidden" }
		end
		return nil
	end,
	state = {
		get = function(k)
			return values[k]
		end,
		set = function(k, v)
			values[k] = v
			if watchers[k] then
				watchers[k](v)
			end
		end,
		watch = function(k, f)
			watchers[k] = f
		end,
	},
	layer = {
		show = function()
			shows = shows + 1
		end,
		hide = function()
			hides = hides + 1
		end,
	},
	runAsync = function(argv, callback)
		if argv[3] == "app-list" then
			pending = callback
		elseif argv[3] == "app-launch" then
			table.insert(launched, argv[4])
			if callback then
				callback({ exitCode = 0 })
			end
		elseif callback then
			callback({ exitCode = 0 })
		end
		return true
	end,
	json = {
		decode = function()
			return apps
		end,
	},
	setUpdateInterval = function() end,
	appIconPath = function(id)
		if id == "missing-override" then
			return nil
		end
		if string.sub(id, 1, 1) == "/" then
			return id
		end
		return "/icons/" .. id
	end,
}
dofile(root .. "/control.luau")
assert(pending ~= nil)
pending({ exitCode = 0, stdout = "fixture" })
assert(#values.apps == 3)
assert(values.ready == true and values.failed == false)
for _ = 1, #apps do
	update() -- finish incremental icon prewarming
end
for _, app in ipairs(values.apps) do
	if app.id == "code" then
		assert(app.icon == "/icons/code-custom.png")
	elseif app.id == "firefox" then
		assert(app.icon == "/icons/firefox") -- bad override falls back to native identity
	end
end
onIpc("toggle")
assert(values.visible and shows == 1 and #values.apps == 3)
onIpc("toggle")
assert(not values.visible and hides > 0)
-- A refresh cannot blank a warm cache, including failure and same-name deduplication.
pending({ exitCode = 1 })
assert(#values.apps == 3)
assert(values.failed == true and values.ready == true)
apps[4] = { id = "duplicate", name = "Firefox", categories = "Network;" }
update()
pending({ exitCode = 0, stdout = "fixture" })
assert(#values.apps == 3)
assert(values.failed == false and values.ready == true)

-- Drawer integration: run the real drawer.luau against a minimal ui.*/layer
-- mock. This exercises filtering, chips, selection, paging, throttling and the
-- empty/loading states without a compositor; native rendering stays a real-session check.
local drawerApps = {}
for i = 1, 40 do
	drawerApps[i] = {
		id = string.format("drawer-%02d", i),
		name = string.format("Drawer %02d", i),
		path = string.format("/apps/drawer-%02d.desktop", i),
		categories = (i % 2 == 0) and "Development;" or "Utility;",
		icon = "/icons/drawer-" .. i,
		search = string.lower(string.format("Drawer %02d drawer-%02d", i, i)),
	}
end
table.insert(drawerApps, 1, {
	id = "drawer-hidden",
	name = "Drawer Hidden",
	path = "/apps/hidden.desktop",
	categories = "Utility;",
	icon = false,
	search = "drawer hidden",
})
values.apps, values.ready, values.failed = drawerApps, true, false
local drawerClock = 1000
noctalia.outputs = function()
	return { { name = "eDP-1", width = 1707, height = 1067, focused = true } }
end
noctalia.getSetting = function(path)
	return path == "accessibility.ui_scale" and 1 or nil
end
noctalia.nowMs = function()
	return drawerClock
end
noctalia.notifyError = function() end
local drawn, drawnCount = nil, 0
layer = {
	outputName = function()
		return "eDP-1"
	end,
	render = function(tree)
		drawn = tree
		drawnCount = drawnCount + 1
	end,
	hide = function() end,
	show = function() end,
}
ui = {}
local function ctor(kind)
	return function(props, children)
		return { type = kind, props = props or {}, children = children or {} }
	end
end
for _, kind in ipairs({
	"column",
	"row",
	"box",
	"label",
	"glyph",
	"image",
	"separator",
	"input",
	"button",
	"scroll",
}) do
	ui[kind] = ctor(kind)
end
local function findNode(node, predicate)
	if not node then
		return nil
	end
	if predicate(node) then
		return node
	end
	for _, child in ipairs(node.children) do
		local hit = findNode(child, predicate)
		if hit then
			return hit
		end
	end
	return nil
end
local function findByKey(key)
	return findNode(drawn, function(node)
		return node.props.key == key
	end)
end
local function allNodes(predicate)
	local hits = {}
	local function walk(node)
		if not node then
			return
		end
		if predicate(node) then
			table.insert(hits, node)
		end
		for _, child in ipairs(node.children) do
			walk(child)
		end
	end
	walk(drawn)
	return hits
end
local function drawerCells()
	return allNodes(function(node)
		return node.type == "column"
			and type(node.props.key) == "string"
			and string.sub(node.props.key, 1, 5) == "cell-"
	end)
end
local function drawerLabels()
	local texts = {}
	for _, node in
		ipairs(allNodes(function(node)
			return node.type == "label"
		end))
	do
		table.insert(texts, node.props.text)
	end
	return texts
end
local function hasDrawerLabel(text)
	for _, value in ipairs(drawerLabels()) do
		if value == text then
			return true
		end
	end
	return false
end
local function searchInput()
	return findNode(drawn, function(node)
		return node.type == "input"
	end)
end
local function selectedCell()
	for _, cell in ipairs(drawerCells()) do
		if cell.props.border == "primary/0.30" then
			return cell
		end
	end
	return nil
end
local function cellLabel(cell)
	local label = findNode(cell, function(node)
		return node.type == "label"
	end)
	return label and label.props.text
end
dofile(root .. "/drawer.luau")
assert(drawn ~= nil and drawnCount == 1)
assert(#drawerCells() == 35)
assert(hasDrawerLabel("Drawer 02") and not hasDrawerLabel("Drawer Hidden"))
assert(searchInput() ~= nil and searchInput().props.focus == true)
assert(searchInput().props.key == "search-0")
assert(#drawerCells() > 0)
assert(findByKey("chip-all").props.fill == "primary/0.16")
assert(findByKey("chip-dev").props.fill == "on_surface/0")
assert(findByKey("dot-1") ~= nil and findByKey("dot-2") ~= nil)
-- Typing filters the grid immediately; an empty result shows the hint.
searchInput().props.onChange("drawer 01")
assert(#drawerCells() == 1 and hasDrawerLabel("Drawer 01"))
assert(findByKey("dot-1") == nil)
searchInput().props.onChange("nope")
assert(hasDrawerLabel("没有匹配的应用"))
assert(findByKey("clear") ~= nil)
findByKey("clear").props.onClick()
assert(#drawerCells() == 35)
-- Category chips switch the list and keep the icon/typing affordances.
findByKey("chip-dev").props.onClick()
assert(findByKey("chip-dev").props.fill == "primary/0.16")
assert(#drawerCells() == 20)
assert(searchInput().props.key ~= "search-0")
findByKey("chip-games").props.onClick()
assert(hasDrawerLabel("这个分类还没有应用"))
findByKey("chip-all").props.onClick()
assert(#drawerCells() == 35)
-- Keyboard selection crosses rows and pages; Enter launches the selected app.
onKey("Right", true)
assert(cellLabel(selectedCell()) == "Drawer 01")
onKey("Down", true)
assert(cellLabel(selectedCell()) == "Drawer 08")
for _ = 1, 4 do
	onKey("Down", true)
end
assert(cellLabel(selectedCell()) == "Drawer 36")
assert(findByKey("dot-2").props.fill == "on_surface/0.85")
onKey("Return", true)
assert(launched[#launched] == "/apps/drawer-36.desktop")
assert(values.visible == false)
-- Wheel paging is throttled; the drawer reopens on the first page.
dofile(root .. "/drawer.luau")
assert(findByKey("dot-1").props.fill == "on_surface/0.85")
onScroll("vertical", "1")
assert(findByKey("dot-2").props.fill == "on_surface/0.85")
onScroll("vertical", "1")
assert(findByKey("dot-2").props.fill == "on_surface/0.85")
drawerClock = drawerClock + 500
onScroll("vertical", "-1")
assert(findByKey("dot-1").props.fill == "on_surface/0.85")
onKey("Escape", true)
assert(values.visible == false)
-- Loading and failure states stay explicit instead of showing an empty grid.
values.apps, values.ready, values.failed = {}, false, false
dofile(root .. "/drawer.luau")
assert(hasDrawerLabel("正在载入应用…"))
values.apps = drawerApps
watchers.apps(drawerApps)
assert(#drawerCells() == 35)
values.apps, values.ready, values.failed = {}, true, true
dofile(root .. "/drawer.luau")
assert(hasDrawerLabel("无法读取应用列表"))
print(
	"Launchpad filtering, pagination, geometry, drawer interaction, empty categories, warm cache, toggle and refresh failure passed"
)
