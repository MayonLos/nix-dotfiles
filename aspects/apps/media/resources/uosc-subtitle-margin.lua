-- Temporary plain-text subtitle clearance for the compact uosc rail.
-- sub-margin-y uses mpv's 720-high scaled pixels. Keep the user's baseline,
-- including live/profile changes; never touch sub-pos or authored ASS styles.
return function(mp)
	local base = mp.get_property_number("sub-margin-y", 34)
	local applied
	local controller = {}

	function controller.update(required)
		local current = mp.get_property_number("sub-margin-y", base)
		-- A value we did not write belongs to the user or a file/profile change.
		if applied == nil or current ~= applied then
			base = current
		end
		local target = math.max(base, math.ceil(required))
		if current ~= target then
			mp.set_property_number("sub-margin-y", target)
		end
		applied = target ~= base and target or nil
	end

	function controller.restore()
		local current = mp.get_property_number("sub-margin-y", base)
		if applied ~= nil and current == applied then
			mp.set_property_number("sub-margin-y", base)
		end
		applied = nil
	end

	mp.register_event("end-file", controller.restore)
	mp.register_event("shutdown", controller.restore)
	return controller
end
