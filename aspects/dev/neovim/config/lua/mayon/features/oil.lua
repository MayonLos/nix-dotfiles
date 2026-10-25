local M = {}
local did_setup = false

local function as_file_path(url)
	local util = require("oil.util")
	local fs = require("oil.fs")
	local scheme, path = util.parse_url(url)
	if not scheme or not path or require("oil.config").adapters[scheme] ~= "files" then
		return nil
	end
	return fs.posix_to_os_path(path)
end

local function protect_files_adapter()
	local files = require("oil.adapters.files")
	if files._mayon_safe_actions then
		return
	end
	local original = files.perform_action
	files.perform_action = function(action, callback)
		local fileops = require("mayon.features.fileops")
		if action.type == "create" then
			local path = as_file_path(action.url)
			if not path then
				return callback("Could not resolve new path")
			end
			local safe, reason = fileops.check_move_target(path)
			if not safe then
				return callback(reason)
			end
		elseif action.type == "copy" then
			local source, destination = as_file_path(action.src_url), as_file_path(action.dest_url)
			if not source or not destination then
				return callback("Only safe local copies are supported")
			end
			local ok, err = fileops.copy_path(source, destination)
			return callback(not ok and err or nil)
		elseif action.type == "delete" then
			local path = as_file_path(action.url)
			if not path then
				return callback("Could not resolve Oil deletion path; item was kept")
			end
			-- The shared trash command leaves source undo files in place.
			-- Oil's recursive_move would also rename the persistent undo file.
			local ok, reason = fileops.trash(path)
			return callback(not ok and reason or nil)
		elseif action.type == "move" then
			local config = require("oil.config")
			local destination_is_files = config.get_adapter_by_scheme(action.dest_url) == files
			if destination_is_files then
				local source = as_file_path(action.src_url)
				local destination = as_file_path(action.dest_url)
				if not destination then
					return callback("Could not resolve Oil move destination; source was kept")
				end
				if source then
					local ok, err = fileops.rename_path(source, destination)
					if ok then
						return callback()
					end
					return callback(err)
				end
				local safe, reason = fileops.check_move_target(destination)
				if not safe then
					return callback(reason)
				end
			end
		end
		return original(action, callback)
	end
	files._mayon_safe_actions = true
end

local function protect_trash_adapter()
	local trash = require("oil.adapters.trash")
	if trash._mayon_safe_actions then
		return
	end
	local original = trash.perform_action
	trash.perform_action = function(action, callback)
		if action.type == "delete" then
			return callback("Permanent deletion from the trash is disabled")
		elseif action.type == "copy" then
			return callback("Copying out of the trash is disabled; restore to a new path instead")
		elseif action.type == "move" then
			local source = as_file_path(action.src_url)
			if source then
				local ok, reason = require("mayon.features.fileops").trash(source)
				return callback(not ok and reason or nil)
			end
			local config = require("oil.config")
			local files = require("oil.adapters.files")
			if config.get_adapter_by_scheme(action.dest_url) == files then
				local fileops = require("mayon.features.fileops")
				local destination = as_file_path(action.dest_url)
				if not destination then
					return callback("Could not resolve restore destination; trashed item was kept")
				end
				local safe, reason = fileops.check_move_target(destination)
				if not safe then
					return callback(reason)
				end
			end
		end
		return original(action, callback)
	end
	trash._mayon_safe_actions = true
end

function M.setup()
	if did_setup then
		return
	end
	local oil = require("oil")
	oil.setup({
		delete_to_trash = true,
		-- fileops owns willRename/didRename and applies edits exactly once, only
		-- after its no-overwrite checks. Oil's parallel implementation would apply
		-- workspace edits before the guarded adapter and duplicate rename events.
		lsp_file_methods = { enabled = false },
		skip_confirm_for_simple_edits = false,
		view_options = { show_hidden = true },
		confirmation = { border = "rounded" },
		float = { border = "rounded" },
	})
	protect_files_adapter()
	protect_trash_adapter()
	vim.keymap.set("n", "-", function()
		oil.open()
	end, { desc = "Browse Parent Directory" })
	did_setup = true
end

return M
