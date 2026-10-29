-- Model and cache lifecycle tests; actual input, native visibility and launch are headless checks.
local root = arg[1]
local modules = {}
require = function(path)
	if not modules[path] then
		modules[path] = dofile(root .. "/" .. string.sub(path, 3))
	end
	return modules[path]
end
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
local values, watchers, pending, shows, hides = {}, {}, nil, 0, 0
noctalia = {
	getConfig = function(key)
		return key == "icon_overrides" and { "code=/icons/code-custom.png", "firefox=missing-override" } or nil
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
update()
update() -- finish incremental icon prewarming
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
apps[4] = { id = "duplicate", name = "Firefox", categories = "Network;" }
update()
pending({ exitCode = 0, stdout = "fixture" })
assert(#values.apps == 3)
print("Launchpad filtering, empty categories, warm cache, toggle and refresh failure passed")
