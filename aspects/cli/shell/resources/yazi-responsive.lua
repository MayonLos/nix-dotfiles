--- @sync entry
-- Yazi 26.5: use the native layout/reflow path, including on terminal resize.
local M = { override = nil, narrow = nil, visible = true }

function M:setup(opts)
	local layout = Tab.layout
	Tab.layout = function(tab)
		local narrow = tab._area.w < opts.min_width
		-- A width transition returns to the automatic layout. A manual override
		-- remains useful within either width range until the next transition.
		if M.narrow ~= narrow then
			M.override = nil
			M.narrow = narrow
		end
		M.visible = M.override
		if M.visible == nil then
			M.visible = not narrow
		end
		rt.mgr.ratio = M.visible and { 0, 5, 4 } or { 0, 1, 0 }
		layout(tab)
	end
end

function M:entry()
	M.override = not M.visible
	ya.emit("app:resize", {})
end

return M
