--!nonstrict
-- 聊天面板 —— 纯显示层。
--
-- 所有状态都在 service.luau 里，这边只读 noctalia.state 渲染、写 state 发指令。
-- 好处是关掉面板对话不丢（panel 的 Lua 状态在关闭时会被销毁）。

-- 面板宽 480 减去内边距。ui.label 没有 wrap 属性（kLabel 只认 width/height/
-- text/fontSize/color/fontWeight/maxWidth/maxLines/textAlign/fontFamily/
-- baseline），换行靠 maxWidth 触发。
local TEXT_WIDTH = 415

local MODELS = { "deepseek-v4-flash", "deepseek-v4-pro" }
local EFFORTS = { "low", "medium", "high" }

local showHistory = false
-- 哪几条消息展开了思考过程，按索引记
local expanded: { [number]: boolean } = {}

-- 输入框是 uncontrolled 的：`value` 只在控件首次创建时播种一次
-- （ui_tree_reconciler.cpp: "Uncontrolled: the host owns the text buffer/cursor.
-- `value` seeds the field once"）。所以要清空或回填历史，只能换掉 key 逼它重建。
local promptSeq = 0
local promptValue = ""

local function setPrompt(text: string)
	promptValue = text
	promptSeq += 1
end

-- 上下键翻历史时的游标：nil = 停在「当前正在输入的那条」
local histCursor: number? = nil

local function messages()
	return noctalia.state.get("ask.messages") or {}
end

local function conversations()
	return noctalia.state.get("ask.conversations") or {}
end

local function status()
	return noctalia.state.get("ask.status") or "idle"
end

local function isThinking(): boolean
	return status() == noctalia.tr("status.thinking")
end

local function currentModel(): string
	return noctalia.state.get("ask.model") or MODELS[1]
end

local function modelIndex(): number
	local m = currentModel()
	for i, v in MODELS do
		if v == m then
			return i - 1 -- ui.select 用 0 基
		end
	end
	return 0
end

local function thinkingOn(): boolean
	return noctalia.state.get("ask.thinking") ~= false
end

local function effortIndex(): number
	local e = noctalia.state.get("ask.effort") or "medium"
	for i, v in EFFORTS do
		if v == e then
			return i - 1
		end
	end
	return 1
end

-- 下拉里显示成「思考:中」这种，比光一个 "medium" 容易懂
local EFFORT_LABELS = {}
for _, v in EFFORTS do
	table.insert(EFFORT_LABELS, noctalia.tr("effort.prefix") .. noctalia.tr("settings.reasoning_effort." .. v))
end

--------------------------------------------------------------------------- 组件

local function bubble(entry, index: number)
	local mine = entry.role == "user"
	local children = {}

	-- 思考过程：默认折叠，点一下展开。放在答案上面，符合阅读顺序。
	if entry.reasoning ~= nil and entry.reasoning ~= "" then
		local open = expanded[index] == true
		table.insert(
			children,
			ui.button({
				text = noctalia.tr(if open then "reasoning.hide" else "reasoning.show"),
				glyph = if open then "chevron-down" else "chevron-right",
				onClick = function()
					expanded[index] = not open
					render()
				end,
			})
		)
		if open then
			table.insert(
				children,
				ui.column({ radius = 8, fill = "surface_variant", padding = 8, align = "stretch" }, {
					-- 思考内容也是模型输出，同样是 markdown
					ui.markdown({ text = entry.reasoning, flexGrow = 1 }),
				})
			)
		end
	end

	-- 气泡用 ui.column 而不是 ui.box：box 的属性集里没有 padding，也不渲染子节点。
	-- 只有 flex 节点（column/row）会递归 children。
	--
	-- 助手回复走 ui.markdown（md4c 支撑，代码块/列表/加粗都能渲染）；
	-- 自己打的字仍用 ui.label —— 输入里随手出现的 * 或 _ 不该被当成格式标记。
	-- kMarkdown 只认 {width,height,flexGrow,opacity,visible,text}，没有
	-- maxWidth/color/fontSize，宽度靠外层 align = "stretch" 撑开。
	table.insert(
		children,
		ui.column({
			radius = 10,
			fill = if mine then "surface_variant" else "surface",
			padding = 10,
			align = "stretch",
		}, {
			if mine
				then ui.label({ text = entry.text, color = "on_surface", maxWidth = TEXT_WIDTH })
				else ui.markdown({ text = entry.text, flexGrow = 1 }),
		})
	)

	return ui.column({ gap = 4, align = "stretch" }, {
		ui.row({ align = "center", gap = 6 }, {
			ui.label({
				text = noctalia.tr(if mine then "role.you" else "role.assistant"),
				fontSize = 11,
				fontWeight = "medium",
				color = if mine then "primary" else "on_surface_variant",
				flexGrow = 1,
			}),
			ui.button({
				glyph = "copy",
				tooltip = noctalia.tr("copied"),
				onClick = function()
					noctalia.copyToClipboard(entry.text, "text/plain")
					noctalia.notify(noctalia.tr("title"), noctalia.tr("copied"))
				end,
			}),
		}),
		ui.column({ gap = 4, align = "stretch" }, children),
	})
end

local function conversationRow(c)
	local active = noctalia.state.get("ask.active") == c.id
	return ui.row({ align = "center", gap = 6 }, {
		ui.button({
			text = c.title,
			flexGrow = 1,
			onClick = function()
				noctalia.state.set("ask.load", c.id)
				showHistory = false
			end,
		}),
		ui.label({
			text = tostring(c.count),
			fontSize = 11,
			color = if active then "primary" else "on_surface_variant",
		}),
		ui.button({
			glyph = "trash",
			onClick = function()
				noctalia.state.set("ask.delete", c.id)
			end,
		}),
	})
end

--------------------------------------------------------------------------- 视图

local function historyView()
	local rows = {}
	local list = conversations()
	-- 新的在上
	for i = #list, 1, -1 do
		table.insert(rows, conversationRow(list[i]))
	end
	if #rows == 0 then
		table.insert(rows, ui.label({
			text = noctalia.tr("history.empty"),
			color = "on_surface_variant",
			maxWidth = TEXT_WIDTH,
		}))
	end
	return rows
end

local function chatView()
	local rows = {}
	for i, entry in messages() do
		table.insert(rows, bubble(entry, i))
	end
	if #rows == 0 then
		table.insert(rows, ui.label({
			text = noctalia.tr("empty"),
			color = "on_surface_variant",
			maxWidth = TEXT_WIDTH,
		}))
	end
	return rows
end

--------------------------------------------------------------------------- 渲染

function render()
	local s = status()
	local thinking = isThinking()
	local canRetry = noctalia.state.get("ask.can_retry") == true

	panel.render(ui.column({ flexGrow = 1, gap = 10 }, {
		ui.row({ align = "center", justify = "space_between", gap = 8 }, {
			ui.label({
				text = if showHistory then noctalia.tr("history.title") else noctalia.tr("title"),
				fontSize = 16,
				fontWeight = "bold",
				flexGrow = 1,
			}),
			ui.button({
				glyph = if showHistory then "message-circle" else "history",
				onClick = function()
					showHistory = not showHistory
					render()
				end,
			}),
			ui.button({
				glyph = "plus",
				onClick = function()
					noctalia.state.set("ask.clear", true)
					showHistory = false
				end,
			}),
			ui.button({ glyph = "close", onClick = "onClose" }),
		}),

		-- 模型和思考强度都放在这里：改一次跑一次的东西不该埋在设置界面里。
		-- 两者都只影响当前会话，不写回设置文件。
		-- 思考关掉时 effort 无意义，置灰而不是隐藏 —— 免得布局跳动。
		ui.row({ gap = 8, align = "center", visible = not showHistory }, {
			ui.select({
				options = MODELS,
				selectedIndex = modelIndex(),
				flexGrow = 1,
				onChange = "onModel",
			}),
			ui.select({
				options = EFFORT_LABELS,
				selectedIndex = effortIndex(),
				enabled = thinkingOn(),
				flexGrow = 1,
				onChange = "onEffort",
			}),
		}),

		ui.scroll({ flexGrow = 1, gap = 12, align = "stretch" }, if showHistory then historyView() else chatView()),

		ui.column({ gap = 6, align = "stretch", visible = not showHistory }, {
			ui.row({ align = "center", gap = 8, visible = s ~= "idle" }, {
				ui.label({
					text = if s == "idle" then "" else s,
					-- thinking 是正常状态，别用错误色
					color = if thinking then "on_surface_variant" else "error",
					fontSize = 11,
					flexGrow = 1,
					maxWidth = TEXT_WIDTH - 80,
				}),
				ui.button({
					text = noctalia.tr("retry"),
					glyph = "refresh",
					visible = canRetry,
					onClick = function()
						noctalia.state.set("ask.retry", true)
					end,
				}),
			}),
			ui.input({
				key = "prompt-" .. tostring(promptSeq),
				value = promptValue,
				placeholder = noctalia.tr(if thinking then "input.waiting" else "input.placeholder"),
				onSubmit = "onSubmit",
			}),
		}),
	}))
end

--------------------------------------------------------------------------- 事件

-- service 那边一有变化就重画
noctalia.state.watch("ask.messages", render)
noctalia.state.watch("ask.status", render)
noctalia.state.watch("ask.conversations", render)
noctalia.state.watch("ask.can_retry", render)
noctalia.state.watch("ask.model", render)
noctalia.state.watch("ask.effort", render)
noctalia.state.watch("ask.thinking", render)

function onOpen(_context)
	render()
end

function onClose()
	panel.close()
end

function onEffort(index, _text)
	local chosen = EFFORTS[(tonumber(index) or 0) + 1]
	if chosen ~= nil then
		noctalia.state.set("ask.set_effort", chosen)
	end
end

function onModel(index, _text)
	local i = (tonumber(index) or 0) + 1
	local chosen = MODELS[i]
	if chosen ~= nil then
		noctalia.state.set("ask.set_model", chosen)
	end
end

function onSubmit(text)
	local question = noctalia.string.trim(text or "")
	if question == "" or isThinking() then
		return
	end
	noctalia.state.set("ask.send", question)
	-- 换 key 让输入框重建成空的；游标回到底部
	setPrompt("")
	histCursor = nil
	render()
end

-- 面板在清单里用 capture_keys 声明了 Up/Down，宿主按下和抬起都会回调，
-- 这里只处理按下。
function onKey(spec, pressed)
	if pressed ~= true then
		return
	end
	local prompts = noctalia.state.get("ask.prompts") or {}
	if #prompts == 0 then
		return
	end

	if spec == "Up" then
		-- 第一次按：从最后一条开始；之后逐条往前
		histCursor = if histCursor == nil then #prompts else math.max(1, histCursor - 1)
		setPrompt(prompts[histCursor])
		render()
	elseif spec == "Down" then
		if histCursor == nil then
			return
		end
		if histCursor >= #prompts then
			-- 走到底了：回到空输入，和 shell 的行为一致
			histCursor = nil
			setPrompt("")
		else
			histCursor += 1
			setPrompt(prompts[histCursor])
		end
		render()
	end
end
