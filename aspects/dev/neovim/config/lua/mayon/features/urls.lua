local M = {}

local urls = M

-- Sentence punctuation and markdown wrappers that sit next to a URL
-- without belonging to it. `*` is here for `**bold link**`.
local ASCII_TRAILERS = "[%.,;:!%?'\"%*%]}>]"

-- Cut by codepoint, not by byte: a URL may legitimately contain non-ASCII
-- (`https://zh.wikipedia.org/wiki/控制论` has to survive), so only these
-- specific marks end one, not "every byte above 0x7f".
local CJK_TERMINATORS = {
	"，",
	"。",
	"；",
	"：",
	"！",
	"？",
	"、",
	"…",
	"（",
	"）",
	"【",
	"】",
	"「",
	"」",
	"《",
	"》",
	"“",
	"”",
	"　",
}

-- These never appear inside a real URL — they would be percent-encoded —
-- so one always ends the URL, including mid-run: `…/x，还有` has no ASCII
-- space to stop the match at, and trimming only the tail would keep 还有.
local function cut_at_cjk(url)
	local cut
	for _, c in ipairs(CJK_TERMINATORS) do
		local s = url:find(c, 1, true)
		if s and (not cut or s < cut) then
			cut = s
		end
	end
	return cut and url:sub(1, cut - 1) or url
end

local function strip_once(url)
	-- A closing paren ends the URL only when nothing inside opened it:
	-- markdown wraps every link in `(...)`, but Wikipedia-style URLs carry
	-- balanced parens that have to survive.
	if url:sub(-1) == ")" then
		local _, opens = url:gsub("%(", "")
		local _, closes = url:gsub("%)", "")
		if closes > opens then
			return url:sub(1, -2)
		end
	end
	return (url:gsub(ASCII_TRAILERS .. "$", ""))
end

local function trim_url(url)
	url = cut_at_cjk(url)
	while true do
		local next_url = strip_once(url)
		if next_url == url then
			return url
		end
		url = next_url
	end
end

-- Earliest URL-ish run at or after `init`. `www.` without a scheme counts;
-- it is flagged so the caller can prepend https.
local function next_match(line, init)
	local s, e = line:find("https?://%S+", init)
	local ws, we = line:find("www%.[%w%-]+%.%S+", init)
	if ws and (not s or ws < s) then
		return ws, we, true
	end
	if s then
		return s, e, false
	end
	return nil
end

--- Every URL on one line, with 1-based byte columns and the markdown link
--- text when the URL is the destination of a `[title](url)`.
function urls.scan(line)
	local found, init = {}, 1
	while init <= #line do
		local s, e, bare = next_match(line, init)
		if not s then
			break
		end
		local url = trim_url(line:sub(s, e))
		if #url > 0 then
			table.insert(found, {
				url = bare and ("https://" .. url) or url,
				from = s,
				to = s + #url - 1,
				title = line:sub(1, s - 1):match("%[([^%]]*)%]%($"),
			})
		end
		init = e + 1
	end
	return found
end

function urls.open(url, quiet)
	local proc, err = vim.ui.open(url)
	if not proc then
		vim.notify("Cannot open " .. url .. ": " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	if not quiet then
		vim.notify(url, vim.log.levels.INFO, { title = "Opened" })
	end
	return true
end

-- --- gx -------------------------------------------------------------

function urls.gx()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1
	local found = urls.scan(line)

	local pick
	for _, u in ipairs(found) do
		if col >= u.from and col <= u.to then
			pick = u
			break
		end
	end
	-- Cursor on the link *text* or on the `- [ ]` checkbox: a notes bullet
	-- is about exactly one link, so the first one on the line is the one
	-- that was meant.
	pick = pick or found[1]

	if pick then
		return urls.open(pick.url)
	end

	-- No URL anywhere on the line: keep the built-in behaviour of opening
	-- whatever path sits under the cursor.
	local cfile = vim.fn.expand("<cfile>")
	if cfile ~= "" then
		return urls.open(cfile)
	end
	vim.notify("No URL under cursor", vim.log.levels.WARN)
end

function urls.gx_visual()
	local region = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)

	local text = table.concat(region, " ")
	local found = urls.scan(text)
	if #found == 0 then
		-- Selecting a bare `example.com` is a deliberate "open this": scan
		-- would not match it because there is no scheme and no `www.`.
		local candidate = vim.trim(text)
		if candidate:match("^[%w%-%.]+%.%a%a+[%w%-%./%?#=&%%]*$") then
			return urls.open("https://" .. candidate)
		end
		vim.notify("No URL in selection", vim.log.levels.WARN)
		return
	end
	for _, u in ipairs(found) do
		urls.open(u.url)
	end
end

-- --- collecting ------------------------------------------------------

function urls.label(entry)
	if entry.title and entry.title ~= "" then
		return entry.title
	end
	-- No markdown title: fall back to the prose around the link, minus the
	-- link itself, so a bare URL still shows whatever context the line has.
	local rest = entry.text:gsub("https?://%S+", ""):gsub("www%.[%w%-]+%.%S+", "")
	rest = rest:gsub("^%s*[%-%*%+]%s*", "") -- bullet
	rest = rest:gsub("^%[[ xX]%]%s*", "") -- checkbox
	rest = rest:gsub("[%[%]%(%)]", "") -- leftovers of a stripped markdown link
	rest = vim.trim(rest:gsub("%s+", " "))
	-- The separator in these notes is an em dash, which is multibyte: it is
	-- matched literally, never inside a `[...]` class, because Lua classes
	-- match single bytes and would slice a Chinese character in half.
	rest = rest:gsub("^—%s*", ""):gsub("%s*—$", "")
	return vim.trim(rest)
end

function urls.from_buffer(bufnr)
	local out = {}
	local lines = vim.api.nvim_buf_get_lines(bufnr or 0, 0, -1, false)
	for lnum, line in ipairs(lines) do
		for _, u in ipairs(urls.scan(line)) do
			table.insert(out, { lnum = lnum, url = u.url, title = u.title, text = line })
		end
	end
	return out
end

function urls.from_dir(dir)
	dir = vim.fn.expand(dir)
	-- rg is supplied by the Nix wrapper; project PATH still takes precedence.
	local ok, res = pcall(function()
		return vim.system({
			"rg",
			"--no-heading",
			"--with-filename",
			"--line-number",
			"--color=never",
			"-e",
			"https?://",
			"--",
			dir,
		}, { text = true }):wait(15000)
	end)
	if not ok then
		vim.notify("rg is not available: " .. tostring(res), vim.log.levels.ERROR)
		return {}
	end
	-- Exit 1 is rg's "no matches", which is a legitimate empty result.
	if res.code ~= 0 and res.code ~= 1 then
		vim.notify("rg failed: " .. (res.stderr or ""), vim.log.levels.ERROR)
		return {}
	end

	local out = {}
	for _, hit in ipairs(vim.split(res.stdout or "", "\n", { trimempty = true })) do
		local file, lnum, text = hit:match("^(.-):(%d+):(.*)$")
		if file then
			for _, u in ipairs(urls.scan(text)) do
				table.insert(out, {
					file = file,
					lnum = tonumber(lnum),
					url = u.url,
					title = u.title,
					text = text,
				})
			end
		end
	end
	return out
end

-- --- picker ----------------------------------------------------------

function urls.pick(entries, opts)
	if #entries == 0 then
		vim.notify("No URLs found", vim.log.levels.WARN)
		return
	end

	local items = {}
	for i, entry in ipairs(entries) do
		local where = entry.file and (vim.fn.fnamemodify(entry.file, ":.") .. ":" .. entry.lnum) or tostring(entry.lnum)
		items[i] = {
			text = where .. "  " .. urls.label(entry) .. "  " .. entry.url,
			url = entry.url,
			file = entry.file or vim.api.nvim_buf_get_name(0),
			pos = { entry.lnum, 0 },
			entry = entry,
		}
	end
	return require("snacks").picker({
		title = opts.prompt,
		items = items,
		format = "text",
		preview = "file",
		confirm = function(picker)
			local selected = picker:selected({ fallback = true })
			picker:close()
			for _, item in ipairs(selected) do
				urls.open(item.url, #selected > 1)
			end
		end,
		actions = {
			url_yank = function(picker)
				local selected = vim.tbl_map(function(item)
					return item.url
				end, picker:selected({ fallback = true }))
				vim.fn.setreg("+", table.concat(selected, "\n"))
				vim.notify(#selected .. " URL(s) yanked", vim.log.levels.INFO)
			end,
			url_source = function(picker, item)
				picker:close()
				if item and item.file and item.file ~= "" then
					vim.cmd.edit(vim.fn.fnameescape(item.file))
				end
				if item then
					pcall(vim.api.nvim_win_set_cursor, 0, item.pos)
				end
			end,
		},
		win = {
			input = {
				keys = {
					["<c-y>"] = { "url_yank", mode = { "n", "i" } },
					["<c-o>"] = { "url_source", mode = { "n", "i" } },
				},
			},
		},
	})
end

function urls.pick_buffer()
	urls.pick(urls.from_buffer(0), { prompt = "URLs (buffer)❯ " })
end

function urls.pick_dir(dir)
	dir = (dir and dir ~= "") and dir or vim.uv.cwd()
	urls.pick(urls.from_dir(dir), { prompt = "URLs " .. vim.fn.fnamemodify(dir, ":t") .. "❯ " })
end

function M.setup()
	vim.api.nvim_create_user_command("Urls", function(cmd)
		urls.pick_dir(cmd.args)
	end, { nargs = "?", complete = "dir", desc = "Pick URL from Directory" })

	vim.api.nvim_create_user_command("UrlsBuffer", urls.pick_buffer, { desc = "Pick URL from Buffer" })
end

return M
