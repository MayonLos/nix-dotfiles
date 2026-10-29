--!nonstrict
local candidate, due, closeAt = nil, 0, 0
local inside = false
local function close()
	candidate, due, closeAt = nil, 0, 0
	noctalia.layer.hide("preview")
	noctalia.setUpdateInterval(30000)
end
function onIpc(event, payload)
	if event == "hover" then
		local context = noctalia.json.decode(payload)
		if type(context) ~= "table" or #context.windows == 0 then
			close()
			return
		end
		candidate, due, closeAt = context, noctalia.nowMs() + 250, 0
		noctalia.setUpdateInterval(25)
	elseif event == "leave" then
		due = 0
		if not inside then
			closeAt = noctalia.nowMs() + 120
			noctalia.setUpdateInterval(25)
		end
	elseif event == "close" then
		close()
	end
end
noctalia.state.watch("inside", function(value)
	inside = value == true
	closeAt = inside and 0 or noctalia.nowMs() + 80
	noctalia.setUpdateInterval(inside and 30000 or 25)
end)
noctalia.state.watch("dismiss", function()
	close()
end)
noctalia.setUpdateInterval(30000)
function update()
	local now = noctalia.nowMs()
	if closeAt > 0 and now >= closeAt and not inside then
		close()
		return
	end
	if due > 0 and now >= due and candidate then
		due = 0
		local c = candidate
		c.cardWidth = math.min(314, c.width - 24)
		c.left = math.clamp(c.x - 38, 12, c.width - c.cardWidth - 12)
		c.arrow = math.clamp(c.x - c.left, 15, c.cardWidth - 15)
		c.cardHeight = math.min(86 + #c.windows * 44, c.height - 60)
		noctalia.state.set("context", c)
		closeAt = 0
		noctalia.layer.configure("preview", {
			output = c.output,
			width = c.cardWidth,
			height = c.cardHeight,
			margins = { left = math.floor(c.left), top = 30 },
		})
		noctalia.layer.show("preview")
		noctalia.setUpdateInterval(30000)
	end
end
function onExit()
	close()
end
