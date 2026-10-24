local source = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fs.dirname(vim.fs.dirname(source))
vim.opt.rtp:prepend(root)

local function tempdir()
	local path = vim.fn.tempname()
	assert(vim.fn.mkdir(path, "p") == 1, "could not create isolated test directory")
	return path
end

local function read(path)
	return table.concat(vim.fn.readfile(path), "\n")
end

local function close_buffer(buf)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

-- Oil's actual files adapter is guarded before deletion. A changed file or
-- any changed descendant of a directory must stop before reaching Oil's trash
-- implementation.
vim.cmd.packadd("oil.nvim")
require("mayon.features.oil").setup()
local oil_config = require("oil.config")
assert(oil_config.delete_to_trash == true, "Oil must route deletion into its trash adapter")
assert(oil_config.skip_confirm_for_simple_edits == false, "Oil must keep confirmations enabled for simple edits")
local files = require("oil.adapters.files")
local oil_fs = require("oil.fs")
local scheme = oil_config.adapter_to_scheme.files
local fileops = require("mayon.features.fileops")
local dir = tempdir()
local modified_path = dir .. "/modified.txt"
vim.fn.writefile({ "disk version" }, modified_path)
vim.cmd.edit(vim.fn.fnameescape(modified_path))
local modified_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(modified_buf, 0, -1, false, { "unsaved version" })
local delete_error
files.perform_action({
	type = "delete",
	url = scheme .. oil_fs.os_to_posix_path(modified_path),
	entry_type = "file",
}, function(err)
	delete_error = err
end)
assert(delete_error and delete_error:find("Unsaved buffer changes", 1, true), "Oil deletion must reject modified files")
assert(read(modified_path) == "disk version", "rejected Oil deletion must keep the disk file")
assert(vim.bo[modified_buf].modified, "rejected Oil deletion must keep unsaved editor text")
close_buffer(modified_buf)

local nested = dir .. "/nested"
local nested_path = nested .. "/child.txt"
vim.fn.mkdir(nested, "p")
vim.fn.writefile({ "nested disk" }, nested_path)
vim.cmd.edit(vim.fn.fnameescape(nested_path))
local nested_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(nested_buf, 0, -1, false, { "nested unsaved" })
local directory_delete_error
files.perform_action({
	type = "delete",
	url = scheme .. oil_fs.os_to_posix_path(nested),
	entry_type = "directory",
}, function(err)
	directory_delete_error = err
end)
assert(
	directory_delete_error and directory_delete_error:find("Unsaved buffer changes", 1, true),
	"Oil directory deletion must reject a modified descendant"
)
assert(read(nested_path) == "nested disk", "rejected directory deletion must preserve the child")
close_buffer(nested_buf)

local trash_adapter = require("oil.adapters.trash")
local purge_error
trash_adapter.perform_action({ type = "delete" }, function(err)
	purge_error = err
end)
assert(purge_error and purge_error:find("Permanent deletion", 1, true), "Oil must refuse to purge trash entries")

local source_path, target_path = dir .. "/source.txt", dir .. "/target.txt"
vim.fn.writefile({ "source" }, source_path)
vim.fn.writefile({ "target" }, target_path)
local move_error
files.perform_action({
	type = "move",
	src_url = scheme .. oil_fs.os_to_posix_path(source_path),
	dest_url = scheme .. oil_fs.os_to_posix_path(target_path),
	entry_type = "file",
}, function(err)
	move_error = err
end)
assert(move_error and move_error:find("Target already exists", 1, true), "Oil move must reject an existing target")
assert(read(source_path) == "source" and read(target_path) == "target", "Oil move must not overwrite a target")

local symlink_path = dir .. "/target-link"
assert(vim.uv.fs_symlink(target_path, symlink_path), "could not create symlink target fixture")
local symlink_error
files.perform_action({
	type = "move",
	src_url = scheme .. oil_fs.os_to_posix_path(source_path),
	dest_url = scheme .. oil_fs.os_to_posix_path(symlink_path),
	entry_type = "file",
}, function(err)
	symlink_error = err
end)
assert(symlink_error and symlink_error:find("Target already exists", 1, true), "Oil move must reject symlink targets")
assert(read(source_path) == "source" and read(target_path) == "target", "symlink target move must preserve both files")

local open_path = dir .. "/open-target.txt"
local open_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(open_buf, open_path)
local open_error
files.perform_action({
	type = "move",
	src_url = scheme .. oil_fs.os_to_posix_path(source_path),
	dest_url = scheme .. oil_fs.os_to_posix_path(open_path),
	entry_type = "file",
}, function(err)
	open_error = err
end)
assert(
	open_error and open_error:find("Target is already open in a buffer", 1, true),
	"Oil move must reject a target buffer even when no file exists yet"
)
assert(vim.fn.filereadable(source_path) == 1, "open target buffer must not move the source")
close_buffer(open_buf)

-- The real adapters must protect cross-adapter trash moves and copies too.
vim.cmd.edit(source_path)
local source_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "unsaved source" })
local trash_move_error
trash_adapter.perform_action(
	{ type = "move", src_url = scheme .. source_path, dest_url = "oil-trash:///", entry_type = "file" },
	function(err)
		trash_move_error = err
	end
)
assert(
	trash_move_error and trash_move_error:find("Unsaved", 1, true),
	"cross-adapter trash move bypassed dirty protection"
)
vim.bo[source_buf].modified = false
close_buffer(source_buf)
local copy_error
files.perform_action(
	{ type = "copy", src_url = scheme .. source_path, dest_url = scheme .. target_path, entry_type = "file" },
	function(err)
		copy_error = err
	end
)
assert(copy_error and read(target_path) == "target", "Oil copy overwrote the target")
local copied_path = dir .. "/copy.txt"
files.perform_action(
	{ type = "copy", src_url = scheme .. source_path, dest_url = scheme .. copied_path, entry_type = "file" },
	function(err)
		assert(not err, err)
	end
)
assert(read(copied_path) == "source", "exclusive Oil copy did not succeed")
local create_error
files.perform_action({ type = "create", url = scheme .. symlink_path, entry_type = "file" }, function(err)
	create_error = err
end)
assert(create_error and read(target_path) == "target", "Oil create adopted a symlink")

local readonly_source, readonly_target = dir .. "/readonly", dir .. "/readonly-copy"
vim.fn.mkdir(readonly_source, "p")
vim.fn.writefile({ "read only" }, readonly_source .. "/child")
vim.fn.setfperm(readonly_source, "r-xr-xr-x")
assert(fileops.copy_path(readonly_source, readonly_target))
assert(read(readonly_target .. "/child") == "read only")
assert(vim.fn.getfperm(readonly_target) == "r-xr-xr-x", "copied directory permissions changed")
vim.fn.setfperm(readonly_source, "rwxr-xr-x")
vim.fn.setfperm(readonly_target, "rwxr-xr-x")
local alias = dir .. "/source-alias"
assert(vim.uv.fs_symlink(readonly_source, alias))
local copied, copy_reason = fileops.copy_path(readonly_source, alias .. "/recursive")
assert(not copied and copy_reason:find("itself", 1, true), "copy followed a target parent symlink into its source")
assert(not vim.uv.fs_lstat(readonly_source .. "/recursive"))
-- Actual shared trash command through Oil, isolated XDG_DATA_HOME, no mock.
local trashed = dir .. "/oil-trash-" .. tostring(vim.uv.hrtime()) .. ".txt"
vim.fn.writefile({ "recoverable" }, trashed)
local source_undo = vim.fn.undofile(trashed)
vim.fn.mkdir(vim.fs.dirname(source_undo), "p")
-- This isolated sentinel proves the adapter never touches source undo paths;
-- ordinary editor undo-format coverage remains in the production wrapper.
vim.fn.writefile({ "undo must remain" }, source_undo)
local deleted, deletion_error
files.perform_action({ type = "delete", url = scheme .. trashed, entry_type = "file" }, function(err)
	deleted = true
	deletion_error = err
end)
assert(
	vim.wait(5000, function()
		return deleted
	end),
	"Oil trash operation did not finish"
)
assert(not deletion_error, deletion_error)
assert(not vim.uv.fs_lstat(trashed), "Oil did not move the file")
assert(read(source_undo) == "undo must remain", "Oil deletion moved or modified source undo")
local matches = vim.fn.glob(vim.env.XDG_DATA_HOME .. "/Trash/files/" .. vim.fs.basename(trashed) .. "*", false, true)
assert(#matches == 1, "Oil trash entry missing")
local trash_file = matches[1]
assert(read(trash_file) == "recoverable", "Oil deletion did not leave a recoverable trash entry")
assert(oil_config.lsp_file_methods.enabled == false, "Oil must not send duplicate LSP rename edits")
vim.fn.delete(dir, "rf")

print("modern Oil and file safety integration checks passed")
