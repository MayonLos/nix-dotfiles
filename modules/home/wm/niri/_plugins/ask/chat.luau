--!nonstrict
-- 聊天面板。
--
-- 密钥每次发送前现读现用，不缓存在插件里：sops 轮换 + rebuild 之后
-- /run/secrets/<name> 会指向新值，下一次提问自动用上，不用重启 noctalia。
--
-- 对话历史只活在这个面板的内存里，不写盘 —— 不想留下聊天记录的副本。

local keyFile = noctalia.getConfig("key_file")
local apiBase = noctalia.getConfig("api_base")
local model = noctalia.getConfig("model")
local systemPrompt = noctalia.getConfig("system_prompt")
local maxTurns = math.max(2, noctalia.getConfig("max_turns") or 12)

-- { role = "user"|"assistant", text = string }
local history: { { role: string, text: string } } = {}
local pending = false
local status = ""

local function readKey(): string?
	local raw = noctalia.readFile(keyFile)
	if raw == nil then
		return nil
	end
	local key = noctalia.string.trim(raw)
	return if key == "" then nil else key
end

-- 面板内容宽度 = 面板宽 460 - 两侧 padding，留点余量给滚动条。
-- label 没有 wrap 属性（kLabel 只认 width/height/text/fontSize/color/fontWeight/
-- maxWidth/maxLines/textAlign/fontFamily/baseline），换行靠 maxWidth 触发。
local TEXT_WIDTH = 400

local function bubble(entry)
	local mine = entry.role == "user"
	-- 气泡用 ui.column 而不是 ui.box：box 的属性集里没有 padding，也不渲染子节点，
	-- 之前气泡是空的就是因为把 label 塞给了 box。flex 才既有 padding/fill/radius
	-- 又会递归children。
	return ui.column({ gap = 2, align = "stretch" }, {
		ui.label({
			text = noctalia.tr(if mine then "role.you" else "role.assistant"),
			fontSize = 11,
			fontWeight = "medium",
			color = if mine then "primary" else "on_surface_variant",
		}),
		ui.column({
			radius = 10,
			fill = if mine then "surface_variant" else "surface",
			padding = 10,
			align = "stretch",
		}, {
			ui.label({ text = entry.text, color = "on_surface", maxWidth = TEXT_WIDTH }),
		}),
	})
end

local function render()
	local rows = {}
	for _, entry in history do
		table.insert(rows, bubble(entry))
	end
	if #history == 0 then
		table.insert(rows, ui.label({ text = noctalia.tr("empty"), color = "on_surface_variant", maxWidth = TEXT_WIDTH }))
	end

	panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
		ui.row({ align = "center", justify = "space_between", gap = 8 }, {
			ui.label({ text = noctalia.tr("title"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
			ui.button({ glyph = "eraser", onClick = "onClear" }),
			ui.button({ glyph = "close", onClick = "onClose" }),
		}),

		ui.scroll({ flexGrow = 1, gap = 12, align = "stretch" }, rows),

		ui.column({ gap = 6, align = "stretch" }, {
			ui.label({
				text = status,
				color = if pending then "on_surface_variant" else "error",
				fontSize = 11,
			}),
			ui.input({
				key = "prompt",
				placeholder = noctalia.tr(if pending then "input.waiting" else "input.placeholder"),
				onSubmit = "onSubmit",
			}),
		}),
	}))
end

-- 只把最近若干轮送上去，避免上下文无限增长把 token 烧光
local function buildMessages(): { { role: string, content: string } }
	local msgs = { { role = "system", content = systemPrompt } }
	local start = math.max(1, #history - maxTurns + 1)
	for i = start, #history do
		table.insert(msgs, { role = history[i].role, content = history[i].text })
	end
	return msgs
end

function onOpen(_context)
	render()
end

function onClose()
	panel.close()
end

function onClear()
	history = {}
	status = ""
	render()
end

function onSubmit(text)
	local question = noctalia.string.trim(text or "")
	if question == "" or pending then
		return
	end

	local key = readKey()
	if key == nil then
		status = noctalia.tr("error.no_key") .. " " .. keyFile
		render()
		return
	end

	table.insert(history, { role = "user", text = question })
	pending = true
	status = noctalia.tr("status.thinking")
	render()

	noctalia.http({
		url = apiBase .. "/chat/completions",
		method = "POST",
		headers = {
			"Authorization: Bearer " .. key,
			"Content-Type: application/json",
		},
		body = noctalia.json.encode({
			model = model,
			messages = buildMessages(),
			stream = false,
		}),
	}, function(res)
		pending = false

		if not res.ok then
			status = string.format(noctalia.tr("error.http"), res.status)
			render()
			return
		end

		local ok, decoded = pcall(noctalia.json.decode, res.body)
		if not ok or decoded == nil then
			status = noctalia.tr("error.decode")
			render()
			return
		end

		-- API 报错时 HTTP 也可能是 200，正文里才有 error
		if decoded.error ~= nil then
			status = decoded.error.message or noctalia.tr("error.api")
			render()
			return
		end

		local choice = decoded.choices and decoded.choices[1]
		local answer = choice and choice.message and choice.message.content
		if answer == nil or answer == "" then
			status = noctalia.tr("error.empty")
			render()
			return
		end

		table.insert(history, { role = "assistant", text = noctalia.string.trim(answer) })
		status = ""
		render()
	end)
end
