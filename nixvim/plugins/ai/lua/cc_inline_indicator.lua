-- Animated buffer indicator for CodeCompanion inline requests: a hatched
-- overlay across the target range, a centred spinner and range signs.
local M = {}
local api = vim.api
local uv = vim.uv or vim.loop
local ns = api.nvim_create_namespace("CodeCompanionInlineIndicator")

local PRIORITY = 2048
local INTERVAL = 100

local SIGN = { first = "┌", body = "│", last = "└", hl = "DiagnosticWarn" }

local Spinner = {}
Spinner.__index = Spinner
local SP_FRAMES = { "⣷", "⣯", "⣟", "⡿", "⢿", "⣻", "⣽", "⣾" }
local SP_TEXT = "  Processing"

function Spinner.new(o)
	local center = (o.width or 0) - vim.fn.strdisplaywidth(SP_TEXT)
	return setmetatable({
		bufnr = o.bufnr,
		row = o.line_num - 1,
		col = center > 0 and math.floor(center / 2) or 0,
		idx = 1,
		timer = uv.new_timer(),
		id = nil,
	}, Spinner)
end

function Spinner:render()
	if not api.nvim_buf_is_valid(self.bufnr) then
		return
	end
	local ok, id = pcall(api.nvim_buf_set_extmark, self.bufnr, ns, self.row, 0, {
		id = self.id,
		virt_text = { { SP_TEXT .. " " .. SP_FRAMES[self.idx] .. " ", "DiagnosticVirtualTextWarn" } },
		virt_text_win_col = self.col,
		priority = PRIORITY + 1,
	})
	if ok then
		self.id = id
	end
end

function Spinner:start()
	self:render()
	self.timer:start(
		0,
		INTERVAL,
		vim.schedule_wrap(function()
			if not self.timer or not api.nvim_buf_is_valid(self.bufnr) then
				return
			end
			self.idx = self.idx % #SP_FRAMES + 1
			self:render()
		end)
	)
end

function Spinner:stop()
	if self.timer then
		self.timer:stop()
		self.timer:close()
		self.timer = nil
	end
	local id, bufnr = self.id, self.bufnr
	if id then
		vim.schedule(function()
			pcall(api.nvim_buf_del_extmark, bufnr, ns, id)
		end)
	end
end

local Block = {}
Block.__index = Block
local BL_RAW = { "╲  ", " ╲ ", "  ╲" }

function Block.new(o)
	local lines = api.nvim_buf_get_lines(o.bufnr, o.start_line - 1, o.end_line, false)
	local maxw = 0
	for _, l in ipairs(lines) do
		maxw = math.max(maxw, vim.fn.strdisplaywidth(l))
	end
	local pw = vim.fn.strdisplaywidth(BL_RAW[1])
	local reps = pw > 0 and math.ceil(maxw / pw) or maxw
	local width = reps * pw
	local hline = string.rep("─", width)
	local patterns = {}
	for _, p in ipairs(BL_RAW) do
		patterns[#patterns + 1] = string.rep(p, reps)
	end
	return setmetatable({
		bufnr = o.bufnr,
		start_row = o.start_line - 1,
		end_row = o.end_line - 1,
		ids = {},
		patterns = patterns,
		idx = 1,
		timer = uv.new_timer(),
		width = width,
		height = #lines,
		border_top = "╭" .. hline .. "╮",
		border_bottom = "╰" .. hline .. "╯",
	}, Block)
end

function Block:virt(row)
	local p = self.patterns[((row + self.idx - 1) % #self.patterns) + 1]
	if self.height <= 2 then
		return { { p, "Comment" } }
	end
	if row == self.start_row then
		return { { self.border_top, "Comment" } }
	end
	if row == self.end_row then
		return { { self.border_bottom, "Comment" } }
	end
	return { { "│" .. p .. "│", "Comment" } }
end

function Block:render(create)
	if not api.nvim_buf_is_valid(self.bufnr) then
		return
	end
	for row = self.start_row, self.end_row do
		local opts = { virt_text = self:virt(row), virt_text_pos = "overlay", priority = PRIORITY }
		if not create then
			opts.id = self.ids[row]
		end
		local ok, id = pcall(api.nvim_buf_set_extmark, self.bufnr, ns, row, 0, opts)
		if ok then
			self.ids[row] = id
		end
	end
end

function Block:start()
	self:render(true)
	self.timer:start(
		0,
		INTERVAL,
		vim.schedule_wrap(function()
			if not self.timer or not api.nvim_buf_is_valid(self.bufnr) then
				return
			end
			self.idx = (self.idx % #self.patterns) + 1
			self:render(false)
		end)
	)
end

function Block:stop()
	if self.timer then
		self.timer:stop()
		self.timer:close()
		self.timer = nil
	end
	local ids, bufnr = self.ids, self.bufnr
	vim.schedule(function()
		for _, id in pairs(ids) do
			pcall(api.nvim_buf_del_extmark, bufnr, ns, id)
		end
	end)
end

local active = nil

local function set_sign(bufnr, line, ch)
	pcall(api.nvim_buf_set_extmark, bufnr, ns, line - 1, 0, {
		sign_text = ch,
		sign_hl_group = SIGN.hl,
		priority = PRIORITY,
	})
end

local function start(bc)
	if active then
		return
	end
	local bufnr, s, e = bc.bufnr, bc.start_line, bc.end_line
	if not (bufnr and s and e and api.nvim_buf_is_valid(bufnr)) then
		return
	end

	local block = Block.new({ bufnr = bufnr, start_line = s, end_line = e })
	local spinner = Spinner.new({
		bufnr = bufnr,
		line_num = s + math.floor((e - s) / 2),
		width = block.width,
	})
	block:start()
	spinner:start()
	active = { bufnr = bufnr, block = block, spinner = spinner }

	if s == e then
		set_sign(bufnr, s, SIGN.body)
	else
		set_sign(bufnr, s, SIGN.first)
		for i = s + 1, e - 1 do
			set_sign(bufnr, i, SIGN.body)
		end
		set_sign(bufnr, e, SIGN.last)
	end
end

local function stop()
	if not active then
		return
	end
	local a = active
	active = nil
	a.spinner:stop()
	a.block:stop()
	if api.nvim_buf_is_valid(a.bufnr) then
		api.nvim_buf_clear_namespace(a.bufnr, ns, 0, -1)
	end
end

function M.setup()
	api.nvim_create_autocmd("User", {
		group = api.nvim_create_augroup("CodeCompanionInlineIndicator", { clear = true }),
		pattern = {
			"CodeCompanionInlineStarted",
			"CodeCompanionInlineFinished",
			"CodeCompanionRequestFinished",
		},
		callback = function(args)
			local data = args.data or {}
			if args.match == "CodeCompanionInlineStarted" then
				if data.status == nil and data.buffer_context then
					start(data.buffer_context)
				end
			elseif args.match == "CodeCompanionInlineFinished" then
				stop()
			elseif data.interaction == "inline" then
				stop()
			end
		end,
	})
end

return M
