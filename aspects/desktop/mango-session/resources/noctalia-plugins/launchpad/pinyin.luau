--!nonstrict
local readings = require("./pinyin-data.luau")
local M = {}
local cache = {}

local function index(name)
	if cache[name] then
		return cache[name]
	end
	local full, initials, hasHan = {}, {}, false
	for _, code in utf8.codes(string.lower(name)) do
		local pronunciation = readings[code]
		if pronunciation then
			hasHan = true
			local words, letters, seen = {}, {}, {}
			for word in string.gmatch(pronunciation, "[^/]+") do
				table.insert(words, word)
				local letter = string.sub(word, 1, 1)
				if not seen[letter] then
					seen[letter] = true
					table.insert(letters, letter)
				end
			end
			table.insert(full, words)
			table.insert(initials, letters)
		elseif code < 128 and string.match(string.char(code), "[%w]") then
			local token = { string.char(code) }
			table.insert(full, token)
			table.insert(initials, token)
		end
	end
	local result = { full = full, initials = initials, hasHan = hasHan }
	cache[name] = result
	return result
end

-- Match a substring through a sequence of pronunciation alternatives. Keeping
-- consumed query lengths avoids expanding exponentially many heteronym strings.
local function contains(tokens, query)
	local previous = {}
	for _, alternatives in ipairs(tokens) do
		local following = {}
		for _, word in ipairs(alternatives) do
			for consumed in pairs(previous) do
				local rest = string.sub(query, consumed + 1)
				if string.sub(word, 1, #rest) == rest then
					return true
				elseif string.sub(rest, 1, #word) == word then
					following[consumed + #word] = true
				end
			end
			for start = 1, #word do
				local suffix = string.sub(word, start)
				if string.sub(suffix, 1, #query) == query then
					return true
				elseif string.sub(query, 1, #suffix) == suffix then
					following[#suffix] = true
				end
			end
		end
		previous = following
	end
	return false
end

function M.rank(name, query)
	if not string.match(query, "^[a-z]+$") then
		return nil
	end
	local data = index(name)
	if data.hasHan then
		if contains(data.initials, query) then
			return 2
		elseif contains(data.full, query) then
			return 4
		end
	end
	return nil
end
return M
