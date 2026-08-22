--!nonstrict
-- Chat panel -- display layer only.
--
-- All state lives in service.luau; this side just reads noctalia.state to
-- render and writes to state to issue commands. The point is that closing the
-- panel does not lose the conversation (a panel's Lua state is destroyed on
-- close).

-- The panel's 480 width minus padding. ui.label has no wrap property (kLabel
-- only knows width/height/text/fontSize/color/fontWeight/maxWidth/maxLines/
-- textAlign/fontFamily/baseline), so wrapping is triggered by maxWidth.
local TEXT_WIDTH = 415

local MODELS = { "deepseek-v4-flash", "deepseek-v4-pro" }
local EFFORTS = { "low", "medium", "high" }

local showHistory = false
-- Which messages have their reasoning expanded, keyed by index
local expanded: { [number]: boolean } = {}

-- The input is uncontrolled: `value` seeds the widget once, when it is first
-- created (ui_tree_reconciler.cpp: "Uncontrolled: the host owns the text
-- buffer/cursor. `value` seeds the field once"). So clearing it or filling in a
-- history entry means swapping the key to force a rebuild.
local promptSeq = 0
local promptValue = ""

local function setPrompt(text: string)
	promptValue = text
	promptSeq += 1
end

-- Cursor for walking history with Up/Down: nil = sitting on what is being typed
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
			return i - 1 -- ui.select is 0-based
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

-- The dropdown reads like "Thinking: medium", which is clearer than a bare
-- "medium"
local EFFORT_LABELS = {}
for _, v in EFFORTS do
	table.insert(EFFORT_LABELS, noctalia.tr("effort.prefix") .. noctalia.tr("settings.reasoning_effort." .. v))
end

--------------------------------------------------------------------- components

local function bubble(entry, index: number)
	local mine = entry.role == "user"
	local children = {}

	-- Reasoning: collapsed by default, one click expands it. Placed above the
	-- answer, which matches the reading order.
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
					-- Reasoning is model output too, so it is markdown as well
					ui.markdown({ text = entry.reasoning, flexGrow = 1 }),
				})
			)
		end
	end

	-- Bubbles use ui.column rather than ui.box: box has no padding in its property
	-- set and does not render children at all -- only flex nodes (column/row)
	-- recurse into children.
	--
	-- Assistant replies go through ui.markdown (backed by md4c, so code blocks,
	-- lists and bold all render); what you typed yourself stays ui.label -- a
	-- stray * or _ in the input should not be read as formatting. kMarkdown only
	-- knows {width,height,flexGrow,opacity,visible,text} and has no
	-- maxWidth/color/fontSize, so the width comes from the outer align = "stretch".
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

-------------------------------------------------------------------------- views

local function historyView()
	local rows = {}
	local list = conversations()
	-- Newest first
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

------------------------------------------------------------------------- render

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

		-- Model and reasoning effort both live here: things you change from one run to
		-- the next do not belong buried in the settings UI. Both affect the current
		-- session only and are never written back to the settings file. With thinking
		-- off the effort is meaningless, so grey it out instead of hiding it -- that
		-- keeps the layout from jumping.
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
					-- thinking is a normal state, so do not use the error color
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

------------------------------------------------------------------------- events

-- Repaint whenever the service changes something
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
	-- Swapping the key rebuilds the input as empty; cursor goes back to the bottom
	setPrompt("")
	histCursor = nil
	render()
end

-- The panel declares Up/Down via capture_keys in the manifest; the host calls
-- back on both press and release, and only press is handled here.
function onKey(spec, pressed)
	if pressed ~= true then
		return
	end
	local prompts = noctalia.state.get("ask.prompts") or {}
	if #prompts == 0 then
		return
	end

	if spec == "Up" then
		-- First press starts at the last entry, then it walks backwards one at a time
		histCursor = if histCursor == nil then #prompts else math.max(1, histCursor - 1)
		setPrompt(prompts[histCursor])
		render()
	elseif spec == "Down" then
		if histCursor == nil then
			return
		end
		if histCursor >= #prompts then
			-- Past the end: back to an empty input, same as a shell does
			histCursor = nil
			setPrompt("")
		else
			histCursor += 1
			setPrompt(prompts[histCursor])
		end
		render()
	end
end
