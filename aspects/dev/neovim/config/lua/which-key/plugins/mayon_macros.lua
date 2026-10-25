-- Use the native plugin item protocol: it preserves the parent @ prefix and
-- the pending count when which-key replays the selected register.
return {
	name = "mayon_macros",
	mappings = {
		plugin = "mayon_macros",
		icon = { icon = "󰑋", hl = "WhichKeyIcon" },
		{ "@", mode = "n", desc = "Run macro" },
	},
	expand = function()
		local items = { { key = "@", desc = "Repeat last macro" } }
		for byte = string.byte("a"), string.byte("z") do
			local register = string.char(byte)
			if vim.fn.getreg(register) ~= "" then
				items[#items + 1] = { key = register, desc = "Run macro " .. register }
			end
		end
		return items
	end,
}
