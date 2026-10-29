-- Exercise ownership and restoration, not the renderer's implementation.
local create = dofile(arg[1])
local value, writes, events
local function fresh(initial)
	value, writes, events = initial, {}, {}
	return create({
		get_property_number = function(name)
			assert(name == "sub-margin-y")
			return value
		end,
		set_property_number = function(name, next_value)
			assert(name == "sub-margin-y")
			value = next_value
			writes[#writes + 1] = next_value
		end,
		register_event = function(name, callback)
			events[name] = callback
		end,
	})
end

local margin = fresh(34)
margin.update(0)
assert(value == 34 and #writes == 0)
margin.update(69.2)
assert(value == 70)
margin.update(69.2)
assert(#writes == 1, "no repeated writes or accumulated offset")
margin.update(110)
assert(value == 110, "resize/fullscreen updates clearance")
margin.update(69.2)
assert(value == 70, "smaller rail releases extra clearance")
margin.update(0)
assert(value == 34, "hide restores the original baseline")
margin.update(69.2)
events["end-file"]()
assert(value == 34)
margin.update(69.2)
events.shutdown()
assert(value == 34)

margin = fresh(130)
margin.update(70)
assert(value == 130 and #writes == 0, "keep an already raised baseline")
margin.update(0)
assert(value == 130)

margin = fresh(34)
margin.update(70)
value = 45 -- User/profile lowers margin while the rail is visible.
margin.update(70)
assert(value == 70)
margin.update(0)
assert(value == 45, "restore the new user baseline")
margin.update(70)
value = 150 -- User raises margin above the required clearance.
margin.update(70)
assert(value == 150)
margin.update(0)
assert(value == 150)

margin = fresh(34)
margin.update(70)
value = 51 -- External write immediately before hide/shutdown must survive.
margin.update(0)
assert(value == 51)
margin.update(70)
value = 92
margin.restore()
assert(value == 92)
print("compact subtitle margin ownership/restoration checks passed")
