--!nonstrict
-- Launchpad drawer. The layer runtime rebuilds this script for every show, so
-- all interaction state here starts fresh: a closed drawer reopens on the "all"
-- category with an empty search.
--
-- Responsibilities are split on purpose:
--   model.luau / pinyin.luau - filtering, categories, pinyin ranking
--   page.luau                - pagination and selection arithmetic
--   layout.luau              - responsive geometry
--   this file                - interaction state + the declarative ui.* tree
local model = require("./model.luau")
local page = require("./page.luau")
local layout = require("./layout.luau")

local PLACEHOLDER = "搜索应用 · 名称或拼音首字母"
local WHEEL_THROTTLE_MS = 110
local PAGE_KEY_THROTTLE_MS = 80
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 1280, 800

local hidden = {}
local hiddenConfig = noctalia.getConfig("hidden_apps")
if type(hiddenConfig) ~= "table" then
	hiddenConfig = {}
end
for _, id in ipairs(hiddenConfig) do
	if type(id) == "string" and id ~= "" then
		hidden[string.lower(id):gsub("%.desktop$", "")] = true
	end
end
local categories = model.list()

-- Logical output size of the surface this layer instance draws on. The runtime
-- scales the ui tree by accessibility.ui_scale, so undo that scaling here.
local function outputGeometry()
	local name = layer.outputName()
	local outputs = noctalia.outputs() or {}
	local matched, focused, first
	for _, output in ipairs(outputs) do
		if type(output) == "table" then
			if not first then
				first = output
			end
			if output.focused then
				focused = output
			end
			if name ~= nil and output.name == name then
				matched = output
			end
		end
	end
	local chosen = matched or focused or first
	local width = tonumber(chosen and chosen.width) or DEFAULT_WIDTH
	local height = tonumber(chosen and chosen.height) or DEFAULT_HEIGHT
	local scale = tonumber(noctalia.getSetting("accessibility.ui_scale")) or 1
	if scale <= 0 then
		scale = 1
	end
	return math.max(320, width / scale), math.max(240, height / scale)
end

local outputWidth, outputHeight = outputGeometry()
local metrics = layout.compute(outputWidth, outputHeight)

local initialApps = noctalia.state.get("apps")
local apps = type(initialApps) == "table" and initialApps or {}
local ready = noctalia.state.get("ready") == true
local failed = noctalia.state.get("failed") == true

local query = ""
local category = "all"
local selected = 0
local pageNumber = 1
local pageCount = 1
local hoveredApp = nil
local hoveredChip = nil
local focusRevision = 0
local lastWheelMs = 0
local lastPageKeyMs = 0

local matches = {}
local categoryAvailable = {}
local appIcons = {}

local filterDirty = true
local chipsDirty = true
local gridDirty = true
local dotsDirty = true
local chipsNode, gridNode, dotsNode

-- Per-app icon/label content cache: icon prewarming publishes a new path for
-- one app at a time, so only that cell is rebuilt.
local cellCache = {}

local render

local function close()
	noctalia.state.set("visible", false)
	noctalia.layer.hide("drawer")
end

local function launch(app)
	if not app or type(app.path) ~= "string" or app.path == "" then
		return
	end
	-- The daemon's AppProvider supplies activation/output routing and systemd policy.
	noctalia.runAsync({ "noctalia", "msg", "app-launch", app.path }, function(result)
		if result and result.exitCode ~= 0 then
			noctalia.notifyError("Launchpad", result.stderr or "")
		end
	end)
	close()
end

local function refreshAvailability()
	categoryAvailable = {}
	for _, cat in ipairs(model.categories(apps)) do
		categoryAvailable[cat.id] = true
	end
end

local function applyFilter()
	filterDirty = false
	matches = model.filter(apps, query, category, hidden)
	pageCount = page.count(#matches, metrics.pageSize)
	pageNumber = page.clampPage(pageNumber, pageCount)
	if selected > #matches then
		selected = 0
	end
	if selected > 0 then
		pageNumber = page.clampPage(page.pageOf(selected, metrics.pageSize), pageCount)
	end
	gridDirty = true
	dotsDirty = true
end

local function currentApp()
	if #matches == 0 then
		return nil
	end
	if selected > 0 then
		return matches[selected]
	end
	local first = page.slice(pageNumber, metrics.pageSize, #matches)
	return matches[first]
end

local function iconChangedOnPage()
	if #matches == 0 then
		return false
	end
	local first, last = page.slice(pageNumber, metrics.pageSize, #matches)
	for index = first, last do
		local app = matches[index]
		if app and app.icon ~= appIcons[app.id] then
			return true
		end
	end
	return false
end

local function buildEmpty()
	local glyphName, title, hint
	if #apps == 0 and not ready and not failed then
		glyphName, title, hint = "apps", "正在载入应用…", "首次打开会自动缓存应用与图标"
	elseif #apps == 0 and failed then
		glyphName, title, hint = "alert-triangle", "无法读取应用列表", "稍后重试，或按 Esc 关闭"
	elseif query ~= "" then
		glyphName, title, hint = "search-off", "没有匹配的应用", "换个关键词，或按 Esc 关闭"
	elseif category ~= "all" then
		glyphName, title, hint = "filter", "这个分类还没有应用", "选择其他分类，或按 Esc 关闭"
	else
		glyphName, title, hint = "apps", "没有可用的应用", "按 Esc 关闭"
	end
	return ui.column({
		key = "grid",
		width = metrics.gridWidth,
		height = metrics.gridHeight,
		align = "center",
		justify = "center",
		gap = 10,
	}, {
		ui.glyph({ key = "empty-icon", name = glyphName, size = 30, color = "on_surface_variant/0.9" }),
		ui.label({
			key = "empty-title",
			text = title,
			fontFamily = "Inter",
			fontSize = 15,
			fontWeight = "medium",
			color = "on_surface",
			textAlign = "center",
		}),
		ui.label({
			key = "empty-hint",
			text = hint,
			fontFamily = "Inter",
			fontSize = 12,
			color = "on_surface_variant",
			textAlign = "center",
		}),
	})
end

local function buildCell(app, index)
	local cached = cellCache[app.id]
	if not cached or cached.icon ~= app.icon then
		local visual = app.icon and ui.image({
			key = "icon",
			path = app.icon,
			width = metrics.iconSize,
			height = metrics.iconSize,
			fit = "contain",
		}) or ui.glyph({
			key = "icon",
			name = "apps",
			size = math.max(18, math.floor(metrics.iconSize * 0.6)),
			color = "on_surface_variant",
		})
		cached = {
			icon = app.icon,
			content = {
				visual,
				ui.label({
					key = "label",
					text = app.name or "",
					fontFamily = "Inter",
					fontSize = metrics.labelSize,
					fontWeight = "medium",
					color = "on_surface",
					width = math.max(24, metrics.cellWidth - 16),
					maxWidth = math.max(24, metrics.cellWidth - 16),
					maxLines = 1,
					textAlign = "center",
				}),
			},
		}
		cellCache[app.id] = cached
		appIcons[app.id] = app.icon
	end
	local isSelected = index == selected
	local isHovered = hoveredApp == app.id
	local fill = "on_surface/0"
	if isSelected then
		fill = isHovered and "primary/0.18" or "primary/0.14"
	elseif isHovered then
		fill = "on_surface/0.07"
	end
	return ui.column({
		key = "cell-" .. app.id,
		width = metrics.cellWidth,
		height = metrics.cellHeight,
		radius = metrics.cellRadius,
		fill = fill,
		border = isSelected and "primary/0.30" or "on_surface/0",
		borderWidth = 1,
		gap = 8,
		align = "center",
		justify = "center",
		onClick = function()
			launch(app)
		end,
		onHover = function(value)
			setHoveredApp(app.id, value == "true")
		end,
	}, cached.content)
end

local function buildGrid()
	if #matches == 0 then
		return buildEmpty()
	end
	local rows = {}
	local first = page.slice(pageNumber, metrics.pageSize, #matches)
	for row = 1, metrics.rows do
		local cells = {}
		for column = 1, metrics.columns do
			local index = first + (row - 1) * metrics.columns + (column - 1)
			local app = matches[index]
			if app then
				table.insert(cells, buildCell(app, index))
			else
				table.insert(
					cells,
					ui.box({
						key = "blank-" .. ((row - 1) * metrics.columns + column),
						width = metrics.cellWidth,
						height = metrics.cellHeight,
						fill = "on_surface/0",
						onClick = close,
					})
				)
			end
		end
		table.insert(
			rows,
			ui.row({
				key = "grid-row-" .. row,
				width = metrics.gridWidth,
				height = metrics.cellHeight,
				gap = metrics.columnGap,
				justify = "center",
			}, cells)
		)
	end
	return ui.column({
		key = "grid",
		width = metrics.gridWidth,
		gap = metrics.rowGap,
		align = "center",
	}, rows)
end

local function buildChips()
	local compact = metrics.contentWidth < 760
	local tiny = metrics.contentWidth < 440
	local paddingH = tiny and 5 or (compact and 8 or 13)
	local gap = tiny and 4 or (compact and 6 or 8)
	local fontSize = tiny and 11 or (compact and 11.5 or 12.5)
	local chips = {}
	for _, cat in ipairs(categories) do
		local isSelected = category == cat.id
		local isHovered = hoveredChip == cat.id
		local available = #apps == 0 or not ready or categoryAvailable[cat.id] == true
		local color = "on_surface_variant"
		if isSelected then
			color = "primary"
		elseif isHovered then
			color = "on_surface"
		elseif not available then
			color = "on_surface_variant/0.55"
		end
		table.insert(
			chips,
			ui.row({
				key = "chip-" .. cat.id,
				height = 28,
				paddingH = paddingH,
				radius = 14,
				align = "center",
				justify = "center",
				fill = isSelected and "primary/0.16" or (isHovered and "on_surface/0.08" or "on_surface/0"),
				border = isSelected and "primary/0.35" or "on_surface/0",
				borderWidth = 1,
				onClick = function()
					selectCategory(cat.id)
				end,
				onHover = function(value)
					setHoveredChip(cat.id, value == "true")
				end,
			}, {
				ui.label({
					key = "chip-label",
					text = cat.label,
					fontFamily = "Inter",
					fontSize = fontSize,
					fontWeight = isSelected and "semibold" or "medium",
					color = color,
				}),
			})
		)
	end
	return ui.row({
		key = "chips",
		width = metrics.contentWidth,
		height = 30,
		gap = gap,
		align = "center",
		justify = "center",
	}, chips)
end

local function buildDots()
	if pageCount <= 1 then
		return ui.row({ key = "dots", width = metrics.contentWidth, height = 16 })
	end
	local dots = {}
	for current = 1, pageCount do
		local isActive = current == pageNumber
		table.insert(
			dots,
			ui.row({
				key = "dot-" .. current,
				width = isActive and 18 or 6,
				height = 6,
				radius = 3,
				fill = isActive and "on_surface/0.85" or "on_surface/0.22",
				onClick = function()
					goToPage(current)
				end,
			})
		)
	end
	return ui.row({
		key = "dots",
		width = metrics.contentWidth,
		height = 16,
		gap = 6,
		align = "center",
		justify = "center",
	}, dots)
end

local function buildSearch()
	local trailing
	if query ~= "" then
		trailing = ui.row({
			key = "clear",
			width = 22,
			height = 22,
			radius = 11,
			align = "center",
			justify = "center",
			fill = "on_surface/0.10",
			onClick = clearSearch,
		}, {
			ui.glyph({ key = "clear-icon", name = "x", size = 12, color = "on_surface_variant" }),
		})
	else
		trailing = ui.row({
			key = "esc-hint",
			width = 34,
			height = 22,
			radius = 11,
			align = "center",
			justify = "center",
			fill = "on_surface/0.08",
			onClick = close,
		}, {
			ui.label({ key = "esc-label", text = "Esc", fontFamily = "Inter", fontSize = 10.5, color = "on_surface_variant" }),
		})
	end
	return ui.row({
		key = "search-frame",
		width = metrics.searchWidth,
		height = 44,
		paddingH = 14,
		gap = 10,
		align = "center",
		radius = 22,
		fill = "on_surface/0.08",
		border = "primary/0.35",
		borderWidth = 1,
		onClick = focusSearch,
	}, {
		ui.glyph({ key = "search-icon", name = "search", size = 16, color = "on_surface_variant" }),
		ui.input({
			key = "search-" .. focusRevision,
			flexGrow = 1,
			height = 30,
			value = query,
			placeholder = PLACEHOLDER,
			fontSize = 15,
			frameVisible = false,
			focus = true,
			onChange = onQueryChanged,
			onSubmit = onQuerySubmitted,
		}),
		trailing,
	})
end

render = function()
	if filterDirty then
		applyFilter()
	end
	if chipsDirty then
		chipsNode = buildChips()
		chipsDirty = false
	end
	if gridDirty then
		gridNode = buildGrid()
		gridDirty = false
	end
	if dotsDirty then
		dotsNode = buildDots()
		dotsDirty = false
	end
	layer.render(ui.column({
		key = "scrim",
		width = metrics.width,
		height = metrics.height,
		align = "center",
		fill = "shadow/0.66",
		onClick = close,
	}, {
		ui.box({ key = "space-top", flexGrow = 1, onClick = close }),
		ui.column({ key = "content", width = metrics.contentWidth, align = "center" }, {
			buildSearch(),
			ui.box({ key = "gap-search", height = 18 }),
			chipsNode,
			ui.box({ key = "gap-chips", height = 22 }),
			gridNode,
			ui.box({ key = "gap-dots", height = 18 }),
			dotsNode,
		}),
		ui.box({ key = "space-bottom", flexGrow = 1, onClick = close }),
		ui.box({ key = "dock-safe", height = metrics.safeBottom, onClick = close }),
	}))
end

function onQueryChanged(value)
	query = type(value) == "string" and value or ""
	selected = 0
	pageNumber = 1
	filterDirty, gridDirty, dotsDirty = true, true, true
	render()
end

function onQuerySubmitted()
	launch(currentApp())
end

function selectCategory(id)
	if category == id then
		return
	end
	category = id
	selected = 0
	pageNumber = 1
	filterDirty, chipsDirty, gridDirty, dotsDirty = true, true, true, true
	-- Clicking a chip moves keyboard focus to it; recreate the field with
	-- focus = true so typing immediately keeps filtering.
	focusRevision = focusRevision + 1
	render()
end

function focusSearch()
	focusRevision = focusRevision + 1
	render()
end

function clearSearch()
	query = ""
	selected = 0
	pageNumber = 1
	filterDirty, gridDirty, dotsDirty = true, true, true
	focusRevision = focusRevision + 1
	render()
end

function setHoveredApp(id, hovered)
	if hovered then
		if hoveredApp ~= id then
			hoveredApp = id
			gridDirty = true
			render()
		end
	elseif hoveredApp == id then
		hoveredApp = nil
		gridDirty = true
		render()
	end
end

function setHoveredChip(id, hovered)
	if hovered then
		if hoveredChip ~= id then
			hoveredChip = id
			chipsDirty = true
			render()
		end
	elseif hoveredChip == id then
		hoveredChip = nil
		chipsDirty = true
		render()
	end
end

function changePage(delta)
	local target = page.clampPage(pageNumber + delta, pageCount)
	if target == pageNumber then
		return
	end
	pageNumber = target
	selected = 0
	gridDirty, dotsDirty = true, true
	render()
end

function goToPage(target)
	target = page.clampPage(target, pageCount)
	if target == pageNumber then
		return
	end
	pageNumber = target
	selected = 0
	gridDirty, dotsDirty = true, true
	focusRevision = focusRevision + 1
	render()
end

function moveSelection(delta)
	if #matches == 0 then
		return
	end
	selected = page.move(selected, delta, #matches)
	local target = page.clampPage(page.pageOf(selected, metrics.pageSize), pageCount)
	if target ~= pageNumber then
		pageNumber = target
		dotsDirty = true
	end
	gridDirty = true
	render()
end

function onScroll(axis, steps)
	if axis ~= "vertical" then
		return
	end
	local amount = tonumber(steps)
	if not amount or amount == 0 then
		return
	end
	local now = noctalia.nowMs()
	if now - lastWheelMs < WHEEL_THROTTLE_MS then
		return
	end
	lastWheelMs = now
	changePage(amount > 0 and 1 or -1)
end

function onKey(chord, pressed)
	if pressed ~= true and pressed ~= "true" then
		return
	end
	if chord == "Escape" or chord == "Super+a" then
		close()
		return
	end
	if chord == "Return" then
		launch(currentApp())
		return
	end
	if chord == "Page_Down" or chord == "Page_Up" then
		local now = noctalia.nowMs()
		if now - lastPageKeyMs < PAGE_KEY_THROTTLE_MS then
			return
		end
		lastPageKeyMs = now
		changePage(chord == "Page_Down" and 1 or -1)
		return
	end
	local delta
	if chord == "Left" then
		delta = -1
	elseif chord == "Right" then
		delta = 1
	elseif chord == "Up" then
		delta = -metrics.columns
	elseif chord == "Down" then
		delta = metrics.columns
	end
	if delta then
		moveSelection(delta)
	end
end

noctalia.state.watch("apps", function(value)
	local incoming = type(value) == "table" and value or {}
	if incoming == apps then
		-- Icon prewarming republishes the same table with one icon resolved.
		if iconChangedOnPage() then
			gridDirty = true
			render()
		end
		return
	end
	apps = incoming
	refreshAvailability()
	-- Drop cached cells for apps that disappeared from the index.
	local current = {}
	for _, app in ipairs(apps) do
		current[app.id] = true
	end
	for id in pairs(cellCache) do
		if not current[id] then
			cellCache[id] = nil
			appIcons[id] = nil
		end
	end
	filterDirty, chipsDirty, gridDirty, dotsDirty = true, true, true, true
	render()
end)

noctalia.state.watch("ready", function(value)
	local nextReady = value == true
	if nextReady ~= ready then
		ready = nextReady
		gridDirty, chipsDirty = true, true
		render()
	end
end)

noctalia.state.watch("failed", function(value)
	local nextFailed = value == true
	if nextFailed ~= failed then
		failed = nextFailed
		gridDirty = true
		render()
	end
end)

refreshAvailability()
render()
