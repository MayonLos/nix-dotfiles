--!nonstrict
local hovered = ""
local entries = {
	{ id = "about", label = "关于本机", argv = { "panel-open", "control-center", "system" } },
	{ id = "settings", label = "系统设置…", argv = { "settings-open" } },
	{ separator = true },
	{ id = "lock", label = "锁定屏幕", hint = "Super+Alt+L", argv = { "session", "lock" } },
	{ id = "suspend", label = "睡眠", argv = { "session", "suspend" } },
	{ id = "reboot", label = "重新启动…", argv = { "panel-open", "session", "reboot" } },
	{ id = "shutdown", label = "关机…", argv = { "panel-open", "session", "shutdown" } },
	{ separator = true },
	{ id = "logout", label = "注销…", argv = { "panel-open", "session", "logout" } },
}
local render
render = function()
	local rows = {}
	for _, entry in ipairs(entries) do
		if entry.separator then
			table.insert(rows, ui.separator({ color = "on_surface/0.07", thickness = 1, spacing = 4 }))
		else
			table.insert(
				rows,
				ui.row({
					key = entry.id,
					height = 29,
					paddingH = 10,
					align = "center",
					justify = "space_between",
					radius = 6,
					fill = hovered == entry.id and "primary/0.18" or "surface/0",
					onHover = function(value)
						hovered = value == "true" and entry.id or ""
						render()
					end,
					onClick = function()
						panel.close()
						local argv = { "noctalia", "msg" }
						for _, a in ipairs(entry.argv) do
							table.insert(argv, a)
						end
						noctalia.runAsync(argv)
					end,
				}, {
					ui.label({ text = entry.label, fontFamily = "Inter", fontSize = 13, color = "on_surface" }),
					ui.label({
						text = entry.hint or "",
						fontFamily = "Inter",
						fontSize = 11,
						color = "outline_variant",
					}),
				})
			)
		end
	end
	panel.render(ui.column({
		width = 230,
		padding = 5,
		radius = 10,
		fill = "surface/0.92",
		border = "on_surface/0.08",
		borderWidth = 1,
	}, rows))
end
function onOpen()
	hovered = ""
	render()
end
render()
