--!nonstrict
-- Bar widget：一个入口图标，点开聊天面板。
--
-- 它同时负责「密钥是否可读」的体检 —— 密钥不可读时图标变警告色，
-- 省得你点开面板才发现问不了。

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
	-- 密钥基本不变，查得勤没意义；rebuild 后 /run/secrets 会换新，
	-- 一分钟一次足够察觉。
	noctalia.setUpdateInterval(60000)
	hasKey = checkKey()
	render()
end

function onClick()
	noctalia.togglePanel("mayon/ask:chat")
end

hasKey = checkKey()
render()
