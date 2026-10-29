-- Exercise width transitions and manual override without mocking rendering.
local layout_calls, resize_calls = 0, 0
Tab = {
	layout = function()
		layout_calls = layout_calls + 1
	end,
}
rt = { mgr = {} }
ya = {
	emit = function(event)
		assert(event == "app:resize")
		resize_calls = resize_calls + 1
	end,
}
local plugin = dofile(arg[1])
plugin:setup({ min_width = 100 })
local tab = { _area = { w = 140 } }
Tab.layout(tab)
assert(rt.mgr.ratio[1] == 0 and rt.mgr.ratio[3] == 4)
plugin:entry()
Tab.layout(tab)
assert(rt.mgr.ratio[3] == 0)
Tab.layout(tab)
assert(rt.mgr.ratio[3] == 0, "manual hide must survive reflow")
tab._area.w = 80
Tab.layout(tab)
assert(rt.mgr.ratio[3] == 0)
plugin:entry()
Tab.layout(tab)
assert(rt.mgr.ratio[3] == 4, "manual preview must work in a narrow window")
tab._area.w = 100
Tab.layout(tab)
assert(rt.mgr.ratio[3] == 4, "widening must restore automatic preview")
assert(layout_calls == 6 and resize_calls == 2)
