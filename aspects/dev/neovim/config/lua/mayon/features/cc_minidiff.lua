-- Compatibility bridge for CodeCompanion inline review, which has no MiniDiff
-- provider. Only inline calls are routed through MiniDiff.
local M = {}
function M.setup()
	local diff = require("mini.diff")
	diff.setup({
		source = {
			name = "manual",
			attach = function()
				return false
			end,
		},
		view = { style = "number" }, -- Gitsigns alone owns the sign column.
		mappings = {
			apply = "",
			reset = "",
			textobject = "",
			goto_first = "",
			goto_prev = "",
			goto_next = "",
			goto_last = "",
		},
	})
	local helpers = require("codecompanion.helpers")
	local original = helpers.show_diff
	helpers.show_diff = function(args)
		if not args.inline then
			return original(args)
		end
		local buf = args.bufnr or vim.api.nvim_get_current_buf()
		if vim.b[buf].mayon_inline_review then
			error("当前缓冲区仍有未审阅的 AI 改写")
		end
		local old_config = vim.b[buf].minidiff_config
		vim.b[buf].minidiff_config = { source = diff.gen_source.none() }
		diff.enable(buf)
		diff.set_ref_text(buf, args.from_lines)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, args.to_lines)
		diff.toggle_overlay(buf)
		local ns = vim.api.nvim_create_namespace("MayonInlineReview")
		local hint = " AI 改写 · ,a 接受 · ,r 拒绝 · 不会自动保存 "
		vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
			virt_lines_above = true,
			virt_lines = { { { hint, "MayonDiffHint" } } },
		})
		local closed = false
		local ui = {}
		local previous = {}
		for _, key in ipairs({ ",a", ",r" }) do
			previous[key] = vim.api.nvim_buf_call(buf, function()
				return vim.fn.maparg(key, "n", false, true)
			end)
		end
		local function close()
			if closed then
				return
			end
			closed = true
			if vim.api.nvim_buf_is_valid(buf) then
				diff.disable(buf)
				vim.b[buf].minidiff_config = old_config
				vim.b[buf].mayon_inline_review = nil
				vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
				for _, key in ipairs({ ",a", ",r" }) do
					pcall(vim.keymap.del, "n", key, { buffer = buf })
					if previous[key].buffer == 1 then
						vim.api.nvim_buf_call(buf, function()
							vim.fn.mapset("n", false, previous[key])
						end)
					end
				end
			end
		end
		ui.diff = {
			from = { lines = vim.deepcopy(args.from_lines) },
			to = { lines = vim.deepcopy(args.to_lines) },
		}
		function ui:close()
			close()
		end
		function ui:remove_inline_marks()
			close()
		end
		local function resolve(accept)
			if closed then
				return
			end
			close()
			if not accept then
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, args.from_lines)
			end
			local callback = (args.keymaps or {})[accept and "on_accept" or "on_reject"]
			if callback then
				callback(ui)
			end
		end
		vim.b[buf].mayon_inline_review = true
		vim.keymap.set("n", ",a", function()
			resolve(true)
		end, { buffer = buf, desc = "Accept Inline Edit" })
		vim.keymap.set("n", ",r", function()
			resolve(false)
		end, { buffer = buf, desc = "Reject Inline Edit" })
		return ui
	end
end
return M
