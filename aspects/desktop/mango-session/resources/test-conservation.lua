-- Exercise asynchronous launch rejection and later recovery without hardware.
local commands, reject, shown = {}, true, nil
noctalia = {
	getConfig = function()
		return "green"
	end,
	setUpdateInterval = function() end,
	notify = function() end,
	runAsync = function(argv, callback)
		commands[#commands + 1] = argv[2]
		if reject then
			return false
		end
		callback({ exitCode = 0, stdout = argv[2] == "status" and "养护\n" or "" })
		return true
	end,
}
barWidget = {
	setVisible = function(value)
		shown = value
	end,
	setGlyph = function() end,
	setGlyphColor = function() end,
	setColor = function() end,
	setText = function() end,
	setTooltip = function() end,
}
dofile(arg[1])
update()
reject = false
update()
assert(#commands == 2 and commands[2] == "status" and shown, "status must recover after runAsync rejection")
reject = true
onClick()
reject = false
onClick()
assert(
	#commands == 5 and commands[4] == "toggle" and commands[5] == "status",
	"click must recover after runAsync rejection"
)
print("Conservation status/click recover after async quota rejection")
