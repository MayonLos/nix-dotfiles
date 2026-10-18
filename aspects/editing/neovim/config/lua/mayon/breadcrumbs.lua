local M = {}

local cache, generations, timers, requests = {}, {}, {}, {}
local debounce_ms = 120
local group

local function visible(buf)
	if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
		return false
	end
	local buftype = vim.bo[buf].buftype
	local renamed_file = buftype == "acwrite" and vim.b[buf].mayon_original_buftype == ""
	if (buftype ~= "" and not renamed_file) or vim.api.nvim_buf_get_name(buf) == "" then
		return false
	end
	if vim.b[buf].mayon_bigfile then
		return false
	end
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
			return true
		end
	end
	return false
end

local function clients(buf)
	local result = {}
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
		local supports = client.supports_method and client:supports_method("textDocument/documentSymbol", buf)
		if supports then
			result[#result + 1] = client
		end
	end
	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

local function pos_le(a, b)
	return a.line < b.line or (a.line == b.line and a.character <= b.character)
end

local function pos_lt(a, b)
	return a.line < b.line or (a.line == b.line and a.character < b.character)
end

local function contains(range, pos)
	return range and range.start and range["end"] and pos_le(range.start, pos) and pos_lt(pos, range["end"])
end

local function kind_name(kind)
	local protocol = vim.lsp.protocol
	for name, value in pairs(protocol.SymbolKind) do
		if type(value) == "number" and value == kind then
			return name
		end
	end
	return tostring(kind or "")
end

local function symbol(item)
	local name, icon = kind_name(item.kind), ""
	local ok, kinds = pcall(require, "mayon.kinds")
	if ok then
		icon = kinds[name] and (kinds[name] .. " ") or ""
	end
	return { name = item.name, kind = name, icon = icon, range = item.range }
end

local function tree_path(items, pos)
	local best
	for _, item in ipairs(items or {}) do
		local range = item.range or (item.location and item.location.range)
		if contains(range, pos) then
			local nested = item.children and tree_path(item.children, pos) or nil
			local path = { symbol(item) }
			if nested then
				for _, child in ipairs(nested) do
					path[#path + 1] = child
				end
			end
			best = path
		end
	end
	return best
end

local function flat_path(items, pos, uri)
	local found = {}
	for _, item in ipairs(items or {}) do
		local range = item.location and item.location.range or item.range
		if (not item.location or not item.location.uri or item.location.uri == uri) and contains(range, pos) then
			found[#found + 1] = { item = item, range = range }
		end
	end
	local function size(range)
		return (range["end"].line - range.start.line) * 1000000000 + range["end"].character - range.start.character
	end
	table.sort(found, function(a, b)
		local as, bs = size(a.range), size(b.range)
		if as == bs then
			return a.item.name < b.item.name
		end
		return as > bs
	end)
	local result = {}
	for _, entry in ipairs(found) do
		local container = entry.item.containerName
		local represented = false
		if container then
			for _, item in ipairs(result) do
				if item.name == container then
					represented = true
				end
			end
		end
		if container and not represented then
			result[#result + 1] = { name = container, kind = "", icon = "", range = nil }
		end
		local value = symbol(entry.item)
		value.range = entry.range
		result[#result + 1] = value
	end
	return #result > 0 and result or nil
end

local function path_for(result, pos, uri)
	if type(result) ~= "table" then
		return nil
	end
	if result[1] and result[1].location then
		return flat_path(result, pos, uri)
	end
	return tree_path(result, pos)
end

local function encoding_position(buf, row, col, encoding)
	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
	local stop = math.min(col, #line)
	if encoding == "utf-8" then
		return { line = row, character = stop }
	end
	local i, units = 1, 0
	while i <= stop do
		local b = line:byte(i)
		local width = b < 0x80 and 1 or (b < 0xE0 and 2 or (b < 0xF0 and 3 or 4))
		if i + width - 1 > stop then
			break
		end
		units = units + (encoding == "utf-16" and width == 4 and 2 or 1)
		i = i + width
	end
	return { line = row, character = units }
end

local function cancel_timer(buf)
	local timer = timers[buf]
	if timer then
		timer:stop()
		timer:close()
		timers[buf] = nil
	end
end

local function invalidate(buf)
	generations[buf] = {}
	cache[buf] = nil
	cancel_timer(buf)
	local request = requests[buf]
	if request then
		requests[buf] = nil
		pcall(request.client.cancel_request, request.client, request.id)
	end
	return generations[buf]
end

local function schedule(buf)
	local generation = invalidate(buf)
	if not visible(buf) then
		return
	end
	local eligible = clients(buf)
	local client = eligible[1]
	if not client then
		return
	end
	local timer = vim.uv.new_timer()
	timers[buf] = timer
	timer:start(
		debounce_ms,
		0,
		vim.schedule_wrap(function()
			if timers[buf] == timer then
				timers[buf] = nil
				timer:close()
			end
			if generation ~= generations[buf] or not visible(buf) then
				return
			end
			local current = clients(buf)[1]
			if not current or current.id ~= client.id then
				return schedule(buf)
			end
			local tick = vim.api.nvim_buf_get_changedtick(buf)
			local request_uri = vim.uri_from_bufnr(buf)
			local params = { textDocument = { uri = request_uri } }
			local request = { client = client, uri = request_uri }
			local ok, sent, request_id = pcall(
				client.request,
				client,
				"textDocument/documentSymbol",
				params,
				function(err, result)
					vim.schedule(function()
						if requests[buf] == request then
							requests[buf] = nil
						end
						if
							generation ~= generations[buf]
							or not vim.api.nvim_buf_is_valid(buf)
							or not vim.api.nvim_buf_is_loaded(buf)
							or vim.api.nvim_buf_get_changedtick(buf) ~= tick
							or vim.uri_from_bufnr(buf) ~= request_uri
						then
							return
						end
						local still_current = clients(buf)[1]
						if not still_current or still_current.id ~= client.id then
							return
						end
						cache[buf] = {
							tick = tick,
							result = not err and result or nil,
							encoding = client.offset_encoding or "utf-16",
							uri = request_uri,
						}
						vim.cmd("redrawstatus")
					end)
				end,
				buf
			)
			if ok and sent then
				request.id = request_id
				requests[buf] = request
			elseif generation == generations[buf] and vim.api.nvim_buf_is_valid(buf) then
				cache[buf] = { tick = tick, result = nil, encoding = client.offset_encoding or "utf-16" }
				vim.cmd("redrawstatus")
			end
		end)
	)
end

function M.get(buf, position)
	buf = buf or vim.api.nvim_get_current_buf()
	local entry = cache[buf]
	if not entry or not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= entry.tick then
		return {}
	end
	local row, col
	if position then
		row, col = position.row, position.col
	else
		local win = vim.fn.bufwinid(buf)
		if win == -1 then
			return {}
		end
		row, col = unpack(vim.api.nvim_win_get_cursor(win))
		row = row - 1
	end
	local pos = encoding_position(buf, row, col, entry.encoding)
	return path_for(entry.result, pos, entry.uri) or {}
end

function M.setup()
	if group then
		return
	end
	group = vim.api.nvim_create_augroup("MayonBreadcrumbs", { clear = true })
	vim.api.nvim_create_autocmd({
		"LspAttach",
		"BufEnter",
		"TextChanged",
		"TextChangedI",
		"BufFilePost",
		"BufWritePost",
	}, {
		group = group,
		callback = function(args)
			local buf = args.buf or vim.api.nvim_get_current_buf()
			schedule(buf)
		end,
	})
	vim.api.nvim_create_autocmd("LspDetach", {
		group = group,
		callback = function(args)
			vim.schedule(function()
				schedule(args.buf)
			end)
		end,
	})
	vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
		group = group,
		callback = function(args)
			invalidate(args.buf)
			cache[args.buf], generations[args.buf] = nil, nil
		end,
	})
	for _, client in ipairs(vim.lsp.get_clients()) do
		for buf in pairs(client.attached_buffers or {}) do
			if visible(buf) then
				schedule(buf)
			end
		end
	end
end

return M
