local M = {}
local last_cache

local function root_for(path)
	local root = vim.fs.root(
		path or vim.fn.getcwd(),
		{ "justfile", "Justfile", "Makefile", "package.json", "flake.nix", ".git" }
	)
	return root or vim.fn.getcwd()
end

local function safe_name(name)
	return type(name) == "string" and name ~= "" and not name:find("[%c%s]")
end

local function add(tasks, seen, root, source, name, command)
	if not safe_name(name) then
		return
	end
	local id = source .. ":" .. name
	if seen[id] then
		return
	end
	seen[id] = true
	tasks[#tasks + 1] = {
		id = id,
		name = name,
		title = name,
		source = source,
		command = command,
		cwd = root,
	}
end

local function discover_just(tasks, seen, root)
	local justfile = vim.fs.find({ "justfile", "Justfile" }, { path = root, upward = false })[1]
	if not justfile or vim.fn.executable("just") ~= 1 then
		return
	end
	local ok, result = pcall(function()
		return vim.system({ "just", "--list", "--unsorted" }, { cwd = root, text = true, timeout = 2000 }):wait()
	end)
	if not ok or not result or result.code ~= 0 then
		return
	end
	for line in result.stdout:gmatch("[^\r\n]+") do
		local name = line:match("^%s+([%w_.%-]+)%s*[#%s]") or line:match("^%s+([%w_.%-]+)%s*$")
		if name and name ~= "Available" then
			add(tasks, seen, root, "just", name, "just -- " .. vim.fn.shellescape(name))
		end
	end
end

local function discover_make(tasks, seen, root)
	local makefile = root .. "/Makefile"
	if vim.fn.filereadable(makefile) ~= 1 then
		return
	end
	local phony = {}
	for _, line in ipairs(vim.fn.readfile(makefile)) do
		if line:match("^%.PHONY%s*:") then
			for name in line:gmatch("([%w_.%-]+)") do
				if name ~= ".PHONY" then
					phony[name] = true
				end
			end
		end
	end
	for _, line in ipairs(vim.fn.readfile(makefile)) do
		if not line:match("^%s") and not line:match("^#") then
			local name = line:match("^([%w_.%-]+)%s*:")
			if name and (phony[name] or not line:find("$", 1, true)) then
				add(tasks, seen, root, "make", name, "make -- " .. vim.fn.shellescape(name))
			end
		end
	end
end

local function discover_package(tasks, seen, root)
	local path = root .. "/package.json"
	if vim.fn.filereadable(path) ~= 1 then
		return
	end
	local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
	if not ok or type(data) ~= "table" or type(data.scripts) ~= "table" then
		return
	end
	for name in pairs(data.scripts) do
		add(tasks, seen, root, "npm", name, "npm run -- " .. vim.fn.shellescape(name))
	end
end

local function discover_flake(tasks, seen, root)
	if vim.fn.filereadable(root .. "/flake.nix") ~= 1 or vim.fn.executable("nix") ~= 1 then
		return
	end
	local machine = vim.uv.os_uname().machine
	if machine == "x86_64" then
		machine = "x86_64"
	elseif machine == "aarch64" or machine == "arm64" then
		machine = "aarch64"
	end
	local system = machine .. (vim.fn.has("mac") == 1 and "-darwin" or "-linux")
	local ok, result = pcall(function()
		return vim.system({ "nix", "eval", "--json", root .. "#apps." .. system }, {
			cwd = root,
			text = true,
			timeout = 2500,
		}):wait()
	end)
	if not ok or not result or result.code ~= 0 then
		return
	end
	local decoded, apps = pcall(vim.json.decode, result.stdout)
	if not decoded or type(apps) ~= "table" then
		return
	end
	for name in pairs(apps) do
		add(tasks, seen, root, "flake", name, "nix run .#" .. vim.fn.shellescape(name))
	end
end

function M.discover(path)
	local root = root_for(path)
	local tasks, seen = {}, {}
	discover_just(tasks, seen, root)
	discover_make(tasks, seen, root)
	discover_package(tasks, seen, root)
	discover_flake(tasks, seen, root)
	table.sort(tasks, function(a, b)
		if a.source == b.source then
			return a.name < b.name
		end
		return a.source < b.source
	end)
	return tasks
end

local function state_path()
	return vim.fn.stdpath("state") .. "/last-task.json"
end

local function save_last(task)
	local path = state_path()
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	local temp = path .. ".tmp." .. tostring(vim.uv.hrtime())
	local saved = {
		root = task.cwd,
		id = task.id,
		name = task.name,
		title = task.title,
		source = task.source,
		command = task.command,
		cwd = task.cwd,
	}
	local ok = vim.fn.writefile({ vim.json.encode(saved) }, temp)
	if ok == 0 then
		vim.uv.fs_rename(temp, path)
		last_cache = saved
	end
end

function M.cached_last()
	return last_cache and vim.deepcopy(last_cache) or nil
end

-- Read the tiny persisted display record away from redraw callbacks. The
-- command is only presentation data here; M.run always rediscovers and
-- validates the task before launching it.
function M.refresh_cached_last(callback)
	vim.schedule(function()
		local path = state_path()
		if vim.fn.filereadable(path) ~= 1 then
			last_cache = nil
		else
			local ok, saved = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
			if ok and type(saved) == "table" and type(saved.root) == "string" and type(saved.id) == "string" then
				if
					type(saved.name) == "string"
					and type(saved.source) == "string"
					and type(saved.command) == "string"
					and type(saved.cwd) == "string"
				then
					last_cache = saved
				else
					last_cache = nil
				end
			else
				last_cache = nil
			end
		end
		if callback then
			callback(M.cached_last())
		end
		if #vim.api.nvim_list_uis() > 0 then
			vim.cmd.redrawtabline()
		end
	end)
end

function M.last()
	local path = state_path()
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end
	local ok, saved = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
	if not ok or type(saved) ~= "table" or type(saved.root) ~= "string" or type(saved.id) ~= "string" then
		return nil
	end
	if last_cache and last_cache.root == saved.root and last_cache.id == saved.id then
		return M.cached_last()
	end
	for _, task in ipairs(M.discover(saved.root)) do
		if task.id == saved.id then
			last_cache = task
			return task
		end
	end
	return nil
end

function M.run(task)
	local root, id
	if type(task) == "string" then
		root, id = vim.fn.getcwd(), task
	elseif type(task) == "table" then
		root, id = task.cwd, task.id
	end
	local validated
	if type(root) == "string" and type(id) == "string" then
		for _, found in ipairs(M.discover(root)) do
			if found.id == id then
				validated = found
				break
			end
		end
	end
	if not validated then
		vim.notify("没有可运行的项目任务", vim.log.levels.WARN, { title = "任务" })
		return false
	end
	save_last(validated)
	require("snacks").terminal(validated.command, {
		cwd = validated.cwd,
		win = { style = "terminal", position = "bottom", height = 0.32, border = "single" },
	})
	return true
end

function M.run_last()
	local task = M.cached_last() or M.last()
	if not task then
		vim.notify("当前项目没有上次运行的任务", vim.log.levels.INFO, { title = "任务" })
		return false
	end
	return M.run(task)
end

-- Prime the render-safe cache once without adding file or process work to the
-- statusline/toolbar path.
M.refresh_cached_last()

function M.pick(path, callback)
	local tasks = M.discover(path)
	if #tasks == 0 then
		vim.notify(
			"没有发现 just、Make、flake app 或 package.json 任务",
			vim.log.levels.INFO,
			{ title = "任务" }
		)
		return false
	end
	vim.ui.select(tasks, {
		prompt = "运行项目任务",
		format_item = function(task)
			return (task.source .. "  ·  " .. task.title)
		end,
	}, function(task)
		if task then
			if callback then
				callback(task)
			else
				M.run(task)
			end
		end
	end)
	return true
end

return M
