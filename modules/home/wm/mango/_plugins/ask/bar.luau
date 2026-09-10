--!nonstrict
-- Bar widget: a single entry icon that opens the chat panel.
--
-- It doubles as the "is the key readable" health check -- when the key cannot
-- be read the icon turns into its warning variant, so you do not find out only
-- after opening the panel and trying to ask something.

local keyFile = noctalia.getConfig("key_file")

local hasKey = false

local function checkKey(): boolean
	local raw = noctalia.readFile(keyFile)
	if raw == nil then
		return false
	end
	return noctalia.string.trim(raw) ~= ""
end

local function render()
	if hasKey then
		barWidget.setGlyph("message-circle")
		barWidget.setTooltip(noctalia.tr("tooltip.ready"))
	else
		barWidget.setGlyph("message-circle-off")
		barWidget.setTooltip(noctalia.tr("tooltip.no_key") .. "\n" .. keyFile)
	end
end

function update()
	-- The key hardly ever changes, so polling harder buys nothing; /run/secrets is
	-- replaced after a rebuild, and once a minute notices that soon enough.
	noctalia.setUpdateInterval(60000)
	hasKey = checkKey()
	render()
end

function onClick()
	noctalia.togglePanel("mayon/ask:chat")
end

hasKey = checkKey()
render()
