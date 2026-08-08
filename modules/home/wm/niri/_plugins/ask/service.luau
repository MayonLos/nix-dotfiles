--!nonstrict
-- 无头服务：持有对话、发请求、读写历史。
--
-- panel 关闭时它的 Lua 状态会被销毁，所以对话不能住在 panel 里 —— 这是从
-- mimir 学来的结构。panel 只渲染 noctalia.state 里的东西，并通过 state 发指令。
--
-- 状态键（都以 ask. 开头，避免和别的插件撞）：
--   ask.messages       当前对话 { role, text, reasoning }
--   ask.status         "idle" | "thinking" | 错误文本
--   ask.can_retry      上一次请求失败、可以重试
--   ask.model          当前模型（面板可切，不写回设置）
--   ask.conversations  历史会话摘要 { id, title, at, count }
--   ask.active         当前会话 id
-- 指令键（panel 写，这里消费后清空）：
--   ask.send / ask.retry / ask.clear / ask.load / ask.delete / ask.set_model

local keyFile = noctalia.getConfig("key_file")
local apiBase = noctalia.getConfig("api_base")
local systemPrompt = noctalia.getConfig("system_prompt")
local thinkingEnabled = noctalia.getConfig("thinking")
local reasoningEffort = noctalia.getConfig("reasoning_effort")
local maxTurns = math.max(2, noctalia.getConfig("max_turns") or 12)
local persist = noctalia.getConfig("persist_history")
local maxConversations = math.max(1, noctalia.getConfig("max_conversations") or 30)

type Message = { role: string, text: string, reasoning: string? }
type Conversation = { id: string, title: string, at: number, messages: { Message } }

local model = noctalia.getConfig("model")
local messages: { Message } = {}
local conversations: { Conversation } = {}
local activeId: string? = nil
-- 输入框的提示词历史，跨会话保留（像 shell 的 history），只存文本不存回答
local promptHistory: { string } = {}
local pending = false
-- 失败时记住上一个问题，重试不用重新打字
local lastQuestion: string? = nil

--------------------------------------------------------------------------- 持久化

local function historyPath(): string?
	local dir = noctalia.pluginDataDir()
	if not dir then
		return nil
	end
	return dir .. "/history.json"
end

local function saveHistory()
	if not persist then
		return
	end
	local path = historyPath()
	if not path then
		return
	end
	-- 只留最近 N 个会话，避免文件无限增长
	local keep = {}
	local start = math.max(1, #conversations - maxConversations + 1)
	for i = start, #conversations do
		table.insert(keep, conversations[i])
	end
	conversations = keep
	-- 提示词历史比会话短命得多，固定留 100 条
	local prompts = {}
	local pstart = math.max(1, #promptHistory - 100 + 1)
	for i = pstart, #promptHistory do
		table.insert(prompts, promptHistory[i])
	end
	promptHistory = prompts
	noctalia.writeFile(
		path,
		noctalia.json.encode({ version = 2, conversations = conversations, prompts = promptHistory })
	)
end

local function loadHistory()
	if not persist then
		return
	end
	local path = historyPath()
	if not path then
		return
	end
	local raw = noctalia.readFile(path)
	if raw == nil or noctalia.string.trim(raw) == "" then
		return
	end
	local ok, decoded = pcall(noctalia.json.decode, raw)
	if ok and decoded ~= nil then
		if type(decoded.conversations) == "table" then
			conversations = decoded.conversations
		end
		-- version 1 的文件没有 prompts 字段，缺了就是空列表
		if type(decoded.prompts) == "table" then
			promptHistory = decoded.prompts
		end
	end
end

--------------------------------------------------------------------------- 状态发布

-- 会话列表只发摘要：panel 的列表用不到正文，省一次大对象拷贝
local function publishConversations()
	local summary = {}
	for _, c in conversations do
		table.insert(summary, { id = c.id, title = c.title, at = c.at, count = #c.messages })
	end
	noctalia.state.set("ask.conversations", summary)
end

local function publish()
	local copy = {}
	for _, m in messages do
		table.insert(copy, { role = m.role, text = m.text, reasoning = m.reasoning })
	end
	noctalia.state.set("ask.messages", copy)
	noctalia.state.set("ask.active", activeId)
	noctalia.state.set("ask.model", model)
	noctalia.state.set("ask.effort", reasoningEffort)
	noctalia.state.set("ask.thinking", thinkingEnabled)
	noctalia.state.set("ask.prompts", promptHistory)
end

local function setStatus(s: string)
	noctalia.state.set("ask.status", s)
end

-- 失败：留住问题让面板显示重试按钮
local function fail(reason: string)
	pending = false
	setStatus(reason)
	noctalia.state.set("ask.can_retry", lastQuestion ~= nil)
end

--------------------------------------------------------------------------- 会话管理

local function titleFrom(text: string): string
	local t = noctalia.string.trim(text)
	if #t <= 40 then
		return t
	end
	return string.sub(t, 1, 40) .. "…"
end

-- 当前对话落进 conversations：第一次提问建条目，之后就地更新
local function commitActive()
	if #messages == 0 then
		return
	end
	if activeId == nil then
		activeId = tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
		table.insert(conversations, {
			id = activeId,
			title = titleFrom(messages[1].text),
			at = os.time(),
			messages = messages,
		})
	else
		for _, c in conversations do
			if c.id == activeId then
				c.messages = messages
				c.at = os.time()
				break
			end
		end
	end
	saveHistory()
	publishConversations()
end

--------------------------------------------------------------------------- 请求

local function readKey(): string?
	local raw = noctalia.readFile(keyFile)
	if raw == nil then
		return nil
	end
	local key = noctalia.string.trim(raw)
	return if key == "" then nil else key
end

-- 只把最近若干轮送上去，避免上下文无限增长把 token 烧光。
-- 思考内容不回传 —— 那是给人看的，喂回去只是浪费 token。
local function buildMessages()
	local msgs = { { role = "system", content = systemPrompt } }
	local start = math.max(1, #messages - maxTurns + 1)
	for i = start, #messages do
		table.insert(msgs, { role = messages[i].role, content = messages[i].text })
	end
	return msgs
end

-- send(question, isRetry)：重试时不重复往历史里塞同一个问题
local function send(question: string, isRetry: boolean)
	if pending then
		return
	end

	-- 密钥现读现用，不缓存：sops 轮换 + rebuild 之后下一次提问自动用新的
	local key = readKey()
	if key == nil then
		lastQuestion = question
		fail(noctalia.tr("error.no_key") .. " " .. keyFile)
		return
	end

	if not isRetry then
		table.insert(messages, { role = "user", text = question })
		-- 和上一条相同就不重复记，免得连按回车塞满历史
		if promptHistory[#promptHistory] ~= question then
			table.insert(promptHistory, question)
		end
	end
	lastQuestion = question
	pending = true
	noctalia.state.set("ask.can_retry", false)
	publish()
	setStatus(noctalia.tr("status.thinking"))

	local body: any = {
		model = model,
		messages = buildMessages(),
		stream = false,
	}
	-- V4 的思考模式开关。关掉时显式传 disabled，别依赖服务端默认。
	body.thinking = { type = if thinkingEnabled then "enabled" else "disabled" }
	if thinkingEnabled then
		body.reasoning_effort = reasoningEffort
	end

	noctalia.http({
		url = apiBase .. "/chat/completions",
		method = "POST",
		headers = {
			"Authorization: Bearer " .. key,
			"Content-Type: application/json",
		},
		body = noctalia.json.encode(body),
	}, function(res)
		pending = false

		if not res.ok then
			fail(string.format(noctalia.tr("error.http"), res.status))
			return
		end

		local ok, decoded = pcall(noctalia.json.decode, res.body)
		if not ok or decoded == nil then
			fail(noctalia.tr("error.decode"))
			return
		end

		-- 接口报错时 HTTP 也可能是 200，正文里才有 error
		if decoded.error ~= nil then
			fail(decoded.error.message or noctalia.tr("error.api"))
			return
		end

		local choice = decoded.choices and decoded.choices[1]
		local msg = choice and choice.message
		local answer = msg and msg.content
		if answer == nil or answer == "" then
			fail(noctalia.tr("error.empty"))
			return
		end

		-- 思考内容的字段名各家不一致，两个都认一下
		local reasoning = msg and (msg.reasoning_content or msg.reasoning)
		if reasoning ~= nil then
			reasoning = noctalia.string.trim(reasoning)
			if reasoning == "" then
				reasoning = nil
			end
		end

		table.insert(messages, {
			role = "assistant",
			text = noctalia.string.trim(answer),
			reasoning = reasoning,
		})
		lastQuestion = nil
		setStatus("idle")
		noctalia.state.set("ask.can_retry", false)
		publish()
		commitActive()
	end)
end

--------------------------------------------------------------------------- 指令

noctalia.state.watch("ask.send", function(text)
	if text == nil or text == "" then
		return
	end
	noctalia.state.set("ask.send", nil)
	send(text, false)
end)

-- 重试：问题已经在历史里了，别重复插入
noctalia.state.watch("ask.retry", function(flag)
	if flag ~= true then
		return
	end
	noctalia.state.set("ask.retry", nil)
	if lastQuestion ~= nil then
		send(lastQuestion, true)
	end
end)

noctalia.state.watch("ask.set_effort", function(value)
	if value == nil or value == "" then
		return
	end
	noctalia.state.set("ask.set_effort", nil)
	reasoningEffort = value
	publish()
end)

noctalia.state.watch("ask.set_model", function(value)
	if value == nil or value == "" then
		return
	end
	noctalia.state.set("ask.set_model", nil)
	model = value
	publish()
end)

-- 清空 = 开新对话。已存过的旧对话留在历史里，不动。
noctalia.state.watch("ask.clear", function(flag)
	if flag ~= true then
		return
	end
	noctalia.state.set("ask.clear", nil)
	messages = {}
	activeId = nil
	lastQuestion = nil
	setStatus("idle")
	noctalia.state.set("ask.can_retry", false)
	publish()
end)

noctalia.state.watch("ask.load", function(id)
	if id == nil or id == "" then
		return
	end
	noctalia.state.set("ask.load", nil)
	for _, c in conversations do
		if c.id == id then
			messages = {}
			for _, m in c.messages do
				table.insert(messages, { role = m.role, text = m.text, reasoning = m.reasoning })
			end
			activeId = id
			lastQuestion = nil
			setStatus("idle")
			noctalia.state.set("ask.can_retry", false)
			publish()
			return
		end
	end
end)

noctalia.state.watch("ask.delete", function(id)
	if id == nil or id == "" then
		return
	end
	noctalia.state.set("ask.delete", nil)
	local kept = {}
	for _, c in conversations do
		if c.id ~= id then
			table.insert(kept, c)
		end
	end
	conversations = kept
	if activeId == id then
		messages = {}
		activeId = nil
		publish()
	end
	saveHistory()
	publishConversations()
end)

--------------------------------------------------------------------------- 启动

loadHistory()
publishConversations()
publish()
setStatus("idle")
noctalia.state.set("ask.can_retry", false)

function update()
	-- 全靠事件驱动，不需要轮询
	noctalia.setUpdateInterval(3600000)
end
