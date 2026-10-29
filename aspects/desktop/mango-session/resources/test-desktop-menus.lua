local root = arg[1]
local now, shows, hides, configured = 0, 0, 0, nil
local values, watchers = {}, {}
local fixture
math.clamp = function(n, low, high)
	return math.max(low, math.min(n, high))
end
noctalia = {
	nowMs = function()
		return now
	end,
	json = {
		decode = function()
			return fixture
		end,
	},
	state = {
		get = function(k)
			return values[k]
		end,
		set = function(k, value)
			values[k] = value
			if watchers[k] then
				watchers[k](value)
			end
		end,
		watch = function(k, callback)
			watchers[k] = callback
		end,
	},
	layer = {
		show = function()
			shows = shows + 1
		end,
		hide = function()
			hides = hides + 1
		end,
		configure = function(_, props)
			configured = props
		end,
	},
	setUpdateInterval = function() end,
}
dofile(root .. "/control.luau")
fixture = {
	workspace = "4",
	key = "4",
	output = "HEADLESS-1",
	width = 256,
	height = 500,
	x = 250,
	windows = { { id = "1", appId = "kitty", app = "kitty", title = "first" } },
}
onIpc("hover", "fixture")
now = 249
update()
assert(shows == 0)
now = 250
update()
assert(shows == 1)
assert(configured.width == 232 and configured.margins.left == 12)
assert(values.context.arrow <= configured.width - 15)
noctalia.state.set("inside", true)
onIpc("leave", "")
now = 1000
update()
assert(hides == 0)
noctalia.state.set("inside", false)
now = 1081
update()
assert(hides == 1)
fixture.windows = {}
onIpc("hover", "fixture")
now = 2000
update()
assert(shows == 1)
print("Workspace hover delay, narrow-output clamp, pointer handoff and empty-workspace filtering passed")
