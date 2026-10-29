--!nonstrict
-- The layer is lazy; process-lifetime shared state keeps its index warm.
local refreshing = false
local cachedIcons, iconQueue, indexed = {}, {}, {}
local function refresh()
	if refreshing then
		return
	end
	refreshing = true
	local started = noctalia.runAsync({ "noctalia", "msg", "app-list" }, function(result)
		refreshing = false
		if result.exitCode ~= 0 then
			return
		end
		local apps = noctalia.json.decode(result.stdout)
		if type(apps) ~= "table" then
			return
		end
		local unique, names = {}, {}
		for _, app in ipairs(apps) do
			local name = string.lower(app.name)
			if not names[name] then
				names[name] = true
				app.icon = cachedIcons[app.id] or false
				app.search = string.lower(app.name .. " " .. app.id .. " " .. table.concat(app.aliases or {}, " "))
				table.insert(unique, app)
			end
		end
		table.sort(unique, function(a, b)
			return string.lower(a.name) < string.lower(b.name)
		end)
		indexed = unique
		iconQueue = {}
		for _, app in ipairs(indexed) do
			-- Keep old icons visible while rechecking native identity/theme changes.
			table.insert(iconQueue, app)
		end
		noctalia.state.set("apps", indexed)
		if #iconQueue > 0 then
			noctalia.setUpdateInterval(16)
		end
	end, 10000)
	if not started then
		refreshing = false
	end
end
local function close()
	noctalia.state.set("visible", false)
	noctalia.layer.hide("drawer")
end
function onIpc(event)
	if event == "close" then
		close()
	elseif event == "toggle" then
		if noctalia.state.get("visible") then
			close()
		else
			noctalia.state.set("visible", true)
			noctalia.runAsync({ "noctalia", "msg", "dock-suppress" }, function()
				if noctalia.state.get("visible") then
					noctalia.layer.show("drawer")
				end
			end)
			refresh()
		end
	end
end
noctalia.state.set("visible", false)
noctalia.state.watch("visible", function(visible)
	if not visible then
		noctalia.runAsync({ "noctalia", "msg", "dock-restore" })
		noctalia.layer.hide("drawer")
	end
end)
noctalia.setUpdateInterval(30000)
function update()
	if #iconQueue > 0 then
		-- Bound work per callback: resolving a whole icon theme exceeds Luau's CPU budget.
		for _ = 1, math.min(2, #iconQueue) do
			local app = table.remove(iconQueue, 1)
			cachedIcons[app.id] = noctalia.appIconPath(app.id, 114) or false
			app.icon = cachedIcons[app.id]
		end
		noctalia.state.set("apps", indexed)
		if #iconQueue == 0 then
			noctalia.setUpdateInterval(30000)
		end
	else
		refresh()
	end
end
function onExit()
	-- Detached launch survives service-runtime teardown.
	noctalia.runAsync({ "noctalia", "msg", "dock-restore" })
	close()
end
refresh()
