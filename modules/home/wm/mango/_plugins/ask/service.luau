--!nonstrict
-- Headless service: owns the conversation, sends the requests, reads and writes
-- history.
--
-- A panel's Lua state is destroyed when it closes, so the conversation cannot
-- live in the panel -- this structure is borrowed from mimir. The panel only
-- renders what is in noctalia.state and issues commands through state.
--
-- State keys (all prefixed ask. so they cannot clash with other plugins):
--   ask.messages       current conversation { role, text, reasoning }
--   ask.status         "idle" | "thinking" | error text
--   ask.can_retry      the last request failed and can be retried
--   ask.model          current model (switchable in the panel, never written
--                      back to settings)
--   ask.conversations  summaries of stored conversations { id, title, at, count }
--   ask.active         id of the current conversation
-- Command keys (written by the panel, consumed and cleared here):
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
-- Prompt history for the input, kept across conversations the way a shell's
-- history is; the text only, never the answers
local promptHistory: { string } = {}
local pending = false
-- Remember the last question on failure, so a retry needs no retyping
local lastQuestion: string? = nil

-------------------------------------------------------------------- persistence

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
	-- Keep only the most recent N conversations, so the file cannot grow forever
	local keep = {}
	local start = math.max(1, #conversations - maxConversations + 1)
	for i = start, #conversations do
		table.insert(keep, conversations[i])
	end
	conversations = keep
	-- Prompt history is far more short-lived than conversations; cap it at 100
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
		-- version 1 files have no prompts field; absent means an empty list
		if type(decoded.prompts) == "table" then
			promptHistory = decoded.prompts
		end
	end
end

--------------------------------------------------------------- state publishing

-- Publish summaries only: the panel's list never needs the bodies, which saves
-- copying a large object
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

-- Failure: hold on to the question so the panel can show a retry button
local function fail(reason: string)
	pending = false
	setStatus(reason)
	noctalia.state.set("ask.can_retry", lastQuestion ~= nil)
end

------------------------------------------------------------ conversation store

local function titleFrom(text: string): string
	local t = noctalia.string.trim(text)
	if #t <= 40 then
		return t
	end
	return string.sub(t, 1, 40) .. "…"
end

-- Land the current conversation in conversations: the first question creates
-- the entry, later ones update it in place
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

------------------------------------------------------------------------ request

local function readKey(): string?
	local raw = noctalia.readFile(keyFile)
	if raw == nil then
		return nil
	end
	local key = noctalia.string.trim(raw)
	return if key == "" then nil else key
end

-- Send only the most recent turns, so the context cannot grow without bound and
-- burn through tokens. Reasoning is never sent back -- it is there for a human
-- to read, and feeding it in again only wastes tokens.
local function buildMessages()
	local msgs = { { role = "system", content = systemPrompt } }
	local start = math.max(1, #messages - maxTurns + 1)
	for i = start, #messages do
		table.insert(msgs, { role = messages[i].role, content = messages[i].text })
	end
	return msgs
end

-- send(question, isRetry): a retry must not push the same question into the
-- history twice
local function send(question: string, isRetry: boolean)
	if pending then
		return
	end

	-- The key is read fresh every time and never cached, so the next question
	-- automatically picks up a rotated sops secret after a rebuild
	local key = readKey()
	if key == nil then
		lastQuestion = question
		fail(noctalia.tr("error.no_key") .. " " .. keyFile)
		return
	end

	if not isRetry then
		table.insert(messages, { role = "user", text = question })
		-- Skip a duplicate of the previous entry, so mashing Enter cannot fill the
		-- history
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
	-- V4's thinking-mode switch. When off, pass disabled explicitly rather than
	-- relying on the server-side default.
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

		-- The API can return HTTP 200 on an error; only the body carries `error`
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

		-- Providers disagree on the field name for reasoning, so accept both
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

----------------------------------------------------------------------- commands

noctalia.state.watch("ask.send", function(text)
	if text == nil or text == "" then
		return
	end
	noctalia.state.set("ask.send", nil)
	send(text, false)
end)

-- Retry: the question is already in the history, so do not insert it again
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

-- Clear = start a new conversation. Anything already saved stays in the history
-- untouched.
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

------------------------------------------------------------------------ startup

loadHistory()
publishConversations()
publish()
setStatus("idle")
noctalia.state.set("ask.can_retry", false)

function update()
	-- Fully event-driven, so there is nothing to poll for
	noctalia.setUpdateInterval(3600000)
end
