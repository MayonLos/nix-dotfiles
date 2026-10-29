--!nonstrict
local model = require("./model.luau")
local hidden = {}
for _, id in ipairs(noctalia.getConfig("hidden_apps") or {}) do
	hidden[string.lower(id):gsub("%.desktop$", "")] = true
end
local query, category, selected, page = "", "all", 0, 1
local apps = noctalia.state.get("apps") or {}
local lastScroll = 0
local width, height = 1707, 1067
for _, output in ipairs(noctalia.outputs()) do
	if output.name == layer.outputName() then
		width, height = output.width, output.height
	end
end
local uiScale = noctalia.getSetting("accessibility.ui_scale") or 1
width, height = width / uiScale, height / uiScale
local rows = math.max(1, math.min(5, math.floor((height - 270) / 131)))
local pageSize = rows * 7
local cellWidth = math.min(168, (width - 40) / 7)
local matches = {}
local function close()
	noctalia.state.set("visible", false)
	noctalia.layer.hide("drawer")
end
local function launch(app)
	if not app then
		return
	end
	-- The daemon's AppProvider supplies activation/output routing and systemd policy.
	noctalia.runAsync({ "noctalia", "msg", "app-launch", app.path }, function(result)
		if result.exitCode ~= 0 then
			noctalia.notifyError("Launchpad", result.stderr)
		end
	end)
	close()
end
local render
local function filter()
	matches = model.filter(apps, query, category, hidden)
	page = math.clamp(page, 1, math.max(1, math.ceil(#matches / pageSize)))
	if selected > #matches then
		selected = 0
	end
end
local function changePage(delta)
	local pages = math.max(1, math.ceil(#matches / pageSize))
	page = math.clamp(page + delta, 1, pages)
	selected = 0
	render()
end
render = function()
	filter()
	local categories = {}
	for _, cat in ipairs(model.categories(model.filter(apps, query, "all", hidden))) do
		table.insert(
			categories,
			ui.row({
				key = cat.id,
				paddingH = 12,
				height = 28,
				radius = 14,
				align = "center",
				justify = "center",
				fill = category == cat.id and "on_surface/0.14" or "on_surface/0",
				onClick = function()
					category, page, selected = cat.id, 1, 0
					render()
				end,
			}, {
				ui.label({ text = cat.label, fontSize = 12.5, fontFamily = "Inter", color = "on_surface_variant" }),
			})
		)
	end
	local grid = {}
	for row = 1, rows do
		local cells = {}
		for col = 1, 7 do
			local index = (page - 1) * pageSize + (row - 1) * 7 + col
			local app = matches[index]
			if app then
				local icon = app.icon
				local visual = icon and ui.image({ path = icon, width = 76, height = 76 })
					or ui.glyph({ name = "apps", size = 76, color = "on_surface_variant" })
				table.insert(
					cells,
					ui.column({
						key = app.id,
						width = cellWidth - 36,
						height = 111,
						gap = 9,
						align = "center",
						justify = "center",
						radius = 16,
						fill = selected == index and "on_surface/0.10" or "on_surface/0",
						onClick = function()
							launch(app)
						end,
					}, {
						visual,
						ui.label({
							text = app.name,
							fontFamily = "Inter",
							fontSize = 12.5,
							color = "on_surface",
							width = cellWidth - 40,
							maxWidth = cellWidth - 40,
							maxLines = 1,
							textAlign = "center",
						}),
					})
				)
			else
				table.insert(
					cells,
					ui.box({ width = cellWidth - 36, height = 111, fill = "on_surface/0", onClick = close })
				)
			end
		end
		table.insert(grid, ui.row({ width = cellWidth * 7, gap = 36, paddingH = 18, height = 111 }, cells))
	end
	if #matches == 0 then
		grid = {
			ui.label({
				text = "没有匹配的应用",
				fontFamily = "Inter",
				fontSize = 14,
				color = "on_surface_variant",
			}),
		}
	end
	local dots = {}
	for p = 1, math.max(1, math.ceil(#matches / pageSize)) do
		table.insert(
			dots,
			ui.box({
				key = tostring(p),
				width = 7,
				height = 7,
				radius = 4,
				fill = p == page and "on_surface" or "on_surface/0.35",
				onClick = function()
					page, selected = p, 0
					render()
				end,
			})
		)
	end
	layer.render(ui.column({ width = width, height = height, fill = "shadow/0.64" }, {
		ui.column({ width = width, height = height, align = "center", fill = "surface/0.60", onClick = close }, {
			ui.box({ height = math.min(78, height * 0.08), onClick = close }),
			ui.row({
				key = "search-frame",
				width = 326,
				height = 36,
				paddingH = 12,
				gap = 8,
				align = "center",
				radius = 10,
				fill = "on_surface/0.10",
				border = "on_surface/0.14",
				borderWidth = 1,
			}, {
				ui.glyph({ name = "search", size = 15, color = "on_surface_variant" }),
				ui.input({
					key = "search",
					flexGrow = 1,
					height = 34,
					value = "",
					placeholder = "搜索",
					fontSize = 13.5,
					frameVisible = false,
					focus = true,
					onChange = function(value)
						query, page, selected = value, 1, 0
						render()
					end,
					onSubmit = function()
						launch(matches[selected > 0 and selected or (page - 1) * pageSize + 1])
					end,
				}),
			}),
			ui.box({ height = 16, onClick = close }),
			ui.row({ height = 28, gap = 6, align = "center", justify = "center" }, categories),
			ui.box({ height = 32, onClick = close }),
			ui.column({ width = cellWidth * 7, gap = 20, align = "center" }, grid),
			ui.column({ flexGrow = 1, onClick = close }),
			ui.row({ height = 16, gap = 9, align = "center", justify = "center" }, dots),
			ui.box({ height = 104, onClick = close }),
		}),
	}))
end
function onKey(chord, pressed)
	if pressed ~= true and pressed ~= "true" then
		return
	end
	if chord == "Escape" or chord == "Super+a" then
		close()
		return
	end
	if chord == "Page_Down" then
		changePage(1)
		return
	end
	if chord == "Page_Up" then
		changePage(-1)
		return
	end
	if chord == "Return" then
		launch(matches[selected > 0 and selected or (page - 1) * pageSize + 1])
		return
	end
	local delta = ({ Left = -1, Right = 1, Up = -7, Down = 7 })[chord]
	if delta and #matches > 0 then
		if selected == 0 then
			selected = (page - 1) * pageSize + 1
		else
			selected = math.clamp(selected + delta, 1, #matches)
		end
		page = math.floor((selected - 1) / pageSize) + 1
		render()
	end
end
function onScroll(_, steps)
	local now = noctalia.nowMs()
	if now - lastScroll < 220 then
		return
	end
	lastScroll = now
	changePage(tonumber(steps) > 0 and 1 or -1)
end
noctalia.state.watch("apps", function(value)
	apps = value or {}
	render()
end)
render()
