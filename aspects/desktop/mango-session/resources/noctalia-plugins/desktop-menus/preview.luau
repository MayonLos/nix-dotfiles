--!nonstrict
local c = noctalia.state.get("context")
local hovered = ""
local render
local function hover(value)
	noctalia.state.set("inside", value == "true")
end
local function close()
	noctalia.state.set("dismiss", noctalia.nowMs())
end
local function focus(window)
	noctalia.runAsync({ "noctalia", "msg", "window-focus", window.id })
	close()
end
render = function()
	if not c then
		return
	end
	local rows = {}
	local width = c.cardWidth
	for _, window in ipairs(c.windows) do
		local selected = hovered == window.id
		local icon = noctalia.appIconPath(window.appId, 33)
		table.insert(
			rows,
			ui.row({
				key = window.id,
				height = 44,
				gap = 8,
				paddingH = 7,
				radius = 8,
				fill = selected and "primary/0.12" or "surface/0",
				onClick = function()
					focus(window)
				end,
				onHover = function(value)
					hover(value)
					hovered = value == "true" and window.id or ""
					render()
				end,
			}, {
				ui.box({ width = 2, height = 32, radius = 1, fill = selected and "primary" or "primary/0" }),
				icon and ui.image({ path = icon, width = 22, height = 22 })
					or ui.glyph({ name = "apps", size = 22, color = "on_surface_variant" }),
				ui.column({ gap = 2, flexGrow = 1, justify = "center" }, {
					ui.label({
						text = window.app,
						fontFamily = "Inter",
						fontSize = 12.5,
						fontWeight = "semibold",
						color = "on_surface",
						maxWidth = width - 76,
						maxLines = 1,
					}),
					ui.label({
						text = window.title,
						fontFamily = "Inter",
						fontSize = 11,
						color = "on_surface_variant",
						maxWidth = width - 76,
						maxLines = 1,
					}),
				}),
			})
		)
	end
	layer.render(ui.column({ width = width, height = c.cardHeight, fill = "surface/0", onHover = hover }, {
		ui.row({ height = 8, paddingH = c.arrow - 6 }, {
			ui.label({ text = "▲", fontFamily = "Inter", fontSize = 12, color = "surface/0.92", height = 10 }),
		}),
		ui.column({
			width = width,
			height = c.cardHeight - 8,
			padding = 6,
			radius = 12,
			fill = "surface/0.92",
			border = "on_surface/0.08",
			borderWidth = 1,
			gap = 2,
		}, {
			ui.row({ height = 30, paddingH = 8, align = "center", justify = "space_between" }, {
				ui.label({
					text = "工作区 " .. c.workspace,
					fontFamily = "Inter",
					fontSize = 12.5,
					fontWeight = "semibold",
					color = "on_surface",
				}),
				ui.row({ paddingH = 7, height = 19, radius = 10, fill = "on_surface/0.07", align = "center" }, {
					ui.label({
						text = tostring(#c.windows) .. " 个窗口",
						fontSize = 10.5,
						color = "on_surface_variant",
					}),
				}),
			}),
			ui.scroll({ height = math.min(#c.windows * 44, c.cardHeight - 86), gap = 0 }, rows),
			ui.separator({ color = "on_surface/0.06", thickness = 1 }),
			ui.label({
				text = "单击切换到该窗口 · 滚轮切换工作区",
				fontFamily = "Inter",
				fontSize = 10.5,
				color = "outline_variant",
				height = 24,
				textAlign = "center",
			}),
		}),
	}))
end
noctalia.state.watch("context", function(value)
	c = value
	render()
end)
function onScroll(_, steps)
	if tonumber(steps) == 0 then
		return
	end
	noctalia.runAsync({ "noctalia", "msg", "workspace-switch", tonumber(steps) > 0 and "next" or "prev" })
	close()
end
render()
