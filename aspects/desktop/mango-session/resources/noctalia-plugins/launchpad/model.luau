--!nonstrict
local M = {}
local pinyin = require("./pinyin.luau")
-- Desktop IDs remain the launch identity; overrides affect only the picture.
function M.iconOverrides(entries)
	local result = {}
	if type(entries) ~= "table" then
		return result
	end
	for _, entry in ipairs(entries) do
		if type(entry) == "string" then
			local id, icon = string.match(entry, "^([^=]+)=(.+)$")
			if id and icon then
				result[string.lower(id):gsub("%.desktop$", "")] = icon
			end
		end
	end
	return result
end
local definitions = {
	{ id = "all", label = "全部", tokens = {} },
	{ id = "dev", label = "开发", tokens = { "Development" } },
	{ id = "net", label = "网络", tokens = { "Network" } },
	{ id = "office", label = "办公", tokens = { "Office" } },
	{ id = "graphics", label = "图形", tokens = { "Graphics" } },
	{ id = "media", label = "影音", tokens = { "AudioVideo", "Audio", "Video" } },
	{ id = "games", label = "游戏", tokens = { "Game" } },
	{ id = "system", label = "系统", tokens = { "System", "Settings", "Utility" } },
}
-- Ordered chip definitions. Unlike M.categories(), this always reports every
-- category, so the drawer's chip row keeps stable positions while the user
-- types or changes category.
function M.list()
	local result = {}
	for _, cat in ipairs(definitions) do
		table.insert(result, { id = cat.id, label = cat.label })
	end
	return result
end
local function inCategory(app, id)
	if id == "all" then
		return true
	end
	for _, cat in ipairs(definitions) do
		if cat.id == id then
			for _, token in ipairs(cat.tokens) do
				if string.find(";" .. app.categories .. ";", ";" .. token .. ";", 1, true) then
					return true
				end
			end
		end
	end
	return false
end
function M.categories(apps)
	local result = {}
	for _, cat in ipairs(definitions) do
		for _, app in ipairs(apps) do
			if inCategory(app, cat.id) then
				table.insert(result, cat)
				break
			end
		end
	end
	return result
end
function M.filter(apps, query, category, hidden)
	local result = {}
	local ranks, order = {}, {}
	query = string.lower(query)
	for position, app in ipairs(apps) do
		local rank
		if query == "" or string.sub(string.lower(app.name), 1, #query) == query then
			rank = 0
		elseif string.find(string.lower(app.name), query, 1, true) then
			rank = 1
		else
			rank = pinyin.rank(app.name, query)
			-- Localized aliases can contain incidental ASCII substrings (e.g.
			-- File Roller's "afaylu roller"). Prefer intentional Chinese initials.
			if string.find(app.search, query, 1, true) and (rank == nil or rank > 3) then
				rank = 3
			end
		end
		if (query ~= "" or not (hidden or {})[string.lower(app.id)]) and inCategory(app, category) and rank ~= nil then
			ranks[app], order[app] = rank, position
			table.insert(result, app)
		end
	end
	if query ~= "" then
		-- Stable within a match tier: retain incoming usage/order, without touching
		-- the native launch provider's usage records or the empty-query grid.
		table.sort(result, function(a, b)
			if ranks[a] == ranks[b] then
				return order[a] < order[b]
			end
			return ranks[a] < ranks[b]
		end)
	end
	return result
end
return M
