--!nonstrict
-- Launchpad service: owns the cached native app index, icon prewarming and the
-- IPC/dock contract. All rendering lives in drawer.luau; this entry only
-- publishes plain app records plus a small lifecycle phase.
local refreshing = false
local cachedIcons, iconQueue, indexed = {}, {}, {}
local model = require("./model.luau")
local iconOverrides = model.iconOverrides(noctalia.getConfig("icon_overrides"))

local function fail()
	refreshing = false
	noctalia.state.set("failed", true)
end

local function refresh()
	if refreshing then
		return
	end
	refreshing = true
	local started = noctalia.runAsync({ "noctalia", "msg", "app-list" }, function(result)
		refreshing = false
		if not result or result.exitCode ~= 0 then
			noctalia.state.set("failed", true)
			return
		end
		local decoded = noctalia.json.decode(result.stdout or "")
		if type(decoded) ~= "table" then
			noctalia.state.set("failed", true)
			return
		end
		local unique, names = {}, {}
		for _, app in ipairs(decoded) do
			if type(app) == "table" and type(app.id) == "string" and app.id ~= "" then
				local name = type(app.name) == "string" and app.name or app.id
				local nameKey = string.lower(name)
				if name ~= "" and not names[nameKey] then
					names[nameKey] = true
					local aliases = {}
					if type(app.aliases) == "table" then
						for _, alias in ipairs(app.aliases) do
							if type(alias) == "string" then
								table.insert(aliases, alias)
							end
						end
					end
					app.name = name
					app.aliases = aliases
					app.categories = type(app.categories) == "string" and app.categories or ""
					app.path = type(app.path) == "string" and app.path or ""
					-- Keep a stale icon visible across refreshes until its native
					-- lookup resolves again; the drawer only redraws changed cells.
					app.icon = cachedIcons[app.id] or false
					app.search = string.lower(name .. " " .. app.id .. " " .. table.concat(aliases, " "))
					table.insert(unique, app)
				end
			end
		end
		table.sort(unique, function(a, b)
			return string.lower(a.name) < string.lower(b.name)
		end)
		indexed = unique
		iconQueue = {}
		for _, app in ipairs(indexed) do
			table.insert(iconQueue, app)
		end
		-- Publish the phase before the list so the drawer's first render of a
		-- refresh already knows whether the index is authoritative.
		noctalia.state.set("failed", false)
		noctalia.state.set("ready", true)
		noctalia.state.set("apps", indexed)
		if #iconQueue > 0 then
			noctalia.setUpdateInterval(16)
		end
	end, 10000)
	if not started then
		fail()
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
		local app = table.remove(iconQueue, 1)
		local icon = iconOverrides[string.lower(app.id)]
		cachedIcons[app.id] = (icon and noctalia.appIconPath(icon, 114))
			or noctalia.appIconPath(app.id, 114)
			or false
		app.icon = cachedIcons[app.id]
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
