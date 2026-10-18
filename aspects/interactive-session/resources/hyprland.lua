-- Native Hyprland 0.55.4 API; desktop is an immutable Nix-generated profile.
-- No shell startup here: Home Manager starts the shared session services.
local function color(hex, alpha)
	return "rgba(" .. hex:sub(2) .. (alpha or "ff") .. ")"
end

for name, value in pairs(desktop.environment) do
	hl.env(name, value)
end
hl.env("XCURSOR_THEME", desktop.cursor.name)
hl.env("XCURSOR_SIZE", tostring(desktop.cursor.size))
hl.env("HYPRCURSOR_SIZE", tostring(desktop.cursor.size))

hl.monitor({
	output = desktop.display.name,
	mode = string.format("%dx%d@%s", desktop.display.width, desktop.display.height, desktop.display.refresh),
	position = "0x0",
	scale = tostring(desktop.display.scale),
	vrr = 1,
})
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

hl.config({
	general = {
		gaps_in = 6,
		gaps_out = 10,
		border_size = 2,
		resize_on_border = true,
		allow_tearing = false,
		layout = "dwindle",
		col = {
			active_border = { colors = { color(desktop.blue), color(desktop.cyan) }, angle = 45 },
			inactive_border = color(desktop.border),
		},
	},
	decoration = {
		rounding = 12,
		rounding_power = 2,
		active_opacity = 1,
		inactive_opacity = 1,
		fullscreen_opacity = 1,
		dim_inactive = false,
		dim_special = 0.28,
		shadow = { enabled = true, range = 18, render_power = 3, color = color(desktop.black, "59"), offset = { 0, 5 } },
		blur = { enabled = true, size = 6, passes = 2, new_optimizations = true },
	},
	animations = { enabled = not desktop.reducedMotion },
	input = {
		kb_layout = "us",
		numlock_by_default = true,
		repeat_rate = 30,
		repeat_delay = 400,
		follow_mouse = 1,
		touchpad = { natural_scroll = true, tap_to_click = true, disable_while_typing = true },
	},
	cursor = { hide_on_key_press = true, no_warps = true },
	xwayland = { force_zero_scaling = true },
	dwindle = { preserve_split = true },
	scrolling = { column_width = 0.8, fullscreen_on_one_column = true, follow_focus = true },
	misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		background_color = color(desktop.bg),
		focus_on_activate = false,
	},
})

-- A short spatial transition for windows, a softer workspace transition.
-- Noctalia animates its own layers; never double-animate those surfaces.
hl.curve("mayon-out", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1 } } })
hl.curve("mayon-in-out", { type = "bezier", points = { { 0.65, 0 }, { 0.35, 1 } } })
for _, animation in ipairs({
	{ leaf = "windows", speed = 2.4, bezier = "mayon-out" },
	{ leaf = "windowsIn", speed = 2.2, bezier = "mayon-out", style = "popin 94%" },
	{ leaf = "windowsOut", speed = 1.5, bezier = "mayon-out", style = "popin 96%" },
	{ leaf = "fade", speed = 1.8, bezier = "mayon-out" },
	{ leaf = "border", speed = 1.8, bezier = "mayon-out" },
	{ leaf = "workspaces", speed = 2.6, bezier = "mayon-in-out", style = "slidefade 12%" },
	{ leaf = "specialWorkspace", speed = 2, bezier = "mayon-out", style = "fade" },
}) do
	animation.enabled = not desktop.reducedMotion
	hl.animation(animation)
end
hl.animation({ leaf = "layers", enabled = false })

for i = 1, 9 do
	hl.workspace_rule({ workspace = tostring(i), persistent = true, layout = i == 2 and "scrolling" or "dwindle" })
end
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Preserve native transient-parent handling. Only observed application IDs
-- and narrow titles get explicit geometry, never a blanket "dialog" title.
hl.window_rule({ name = "tiled-surfaces", match = { float = false }, no_shadow = true })
hl.window_rule({ name = "floating-surfaces", match = { float = true }, no_shadow = false })
hl.window_rule({
	name = "portal-picker",
	match = { class = "^xdg-desktop-portal-gtk$" },
	float = true,
	center = true,
	size = { "monitor_w*0.62", "monitor_h*0.68" },
	animation = "fade",
})
hl.window_rule({
	name = "noctalia-settings",
	match = { class = "^dev\\.noctalia\\.Noctalia$" },
	float = true,
	center = true,
	size = { "monitor_w*0.68", "monitor_h*0.82" },
	animation = "fade",
})
hl.window_rule({
	name = "image-viewer",
	match = { class = "^swayimg$" },
	float = true,
	center = true,
	size = { "monitor_w*0.60", "monitor_h*0.72" },
})
hl.window_rule({
	name = "file-rename",
	match = { class = "^thunar$", title = "^(Rename|重命名).*" },
	float = true,
	center = true,
	animation = "fade",
})
hl.window_rule({
	name = "firefox-picture-in-picture",
	match = { class = "^[Ff]irefox$", title = "^Picture-in-Picture$" },
	float = true,
	pin = true,
	no_initial_focus = true,
	size = { 480, 270 },
	move = { "(monitor_w-window_w)*0.85", "(monitor_h-window_h)*0.80" },
	animation = "fade",
})
hl.window_rule({ name = "games", match = { class = "^steam_app_.*" }, no_anim = true, rounding = 0 })
hl.window_rule({
	name = "keybindings",
	match = { class = "^mayon-hyprland-help$" },
	float = true,
	center = true,
	size = { "monitor_w*0.65", "monitor_h*0.75" },
})
hl.layer_rule({ name = "noctalia-owned-effects", match = { namespace = "^noctalia-.*" }, no_anim = true, blur = false })

local help = {
	"Hyprland · One Dark Darker",
	"",
	"与 Mango 相同的常用键位；窗口总览使用 Noctalia 列表，不模拟 Mango overview。",
	"",
}
local function bind(keys, action, description, options)
	options = options or {}
	options.description = description
	hl.bind(keys, action, options)
	help[#help + 1] = string.format("%-28s %s", keys, description)
end
local function shell_quote(value)
	return "'" .. value:gsub("'", "'\\''") .. "'"
end
local function shell(keys, command, description, options)
	bind(keys, hl.dsp.exec_cmd(command), description, options)
end
local function noctalia(keys, command, description, options)
	shell(keys, desktop.commands.noctalia .. " msg " .. command, description, options)
end

shell("SUPER + RETURN", desktop.commands.terminal, "终端")
shell("SUPER + B", desktop.commands.browser, "浏览器")
shell("SUPER + E", desktop.commands.files, "文件管理")
noctalia("ALT + SPACE", "panel-toggle launcher", "启动器")
noctalia("SUPER + S", "panel-toggle control-center", "控制中心")
noctalia("SUPER + V", "panel-toggle clipboard", "剪贴板历史")
noctalia("SUPER + ALT + L", "session lock", "锁屏")
noctalia("SUPER + ALT + D", "notification-dnd-toggle", "勿扰模式")
noctalia("SUPER + ALT + I", "caffeine-toggle", "保持唤醒")
noctalia("SUPER + 0", "window-switcher", "窗口列表")
bind("SUPER + Q", hl.dsp.window.close(), "关闭窗口")
bind("SUPER + SPACE", hl.dsp.window.float({ action = "toggle" }), "切换浮动")
bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "maximized" }), "最大化（保留面板）")
bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), "全屏")
bind("SUPER + CTRL + G", hl.dsp.window.pin(), "浮窗跨工作区显示")
bind("SUPER + SHIFT + S", hl.dsp.workspace.toggle_special("tools"), "通用工具工作区")
bind("SUPER + CTRL + S", hl.dsp.window.move({ workspace = "special:tools", follow = false }), "收纳当前窗口")

for _, item in ipairs({
	{ "H", "left" },
	{ "J", "down" },
	{ "K", "up" },
	{ "L", "right" },
	{ "left", "left" },
	{ "down", "down" },
	{ "up", "up" },
	{ "right", "right" },
}) do
	bind("SUPER + " .. item[1], hl.dsp.focus({ direction = item[2] }), "聚焦 " .. item[2])
	bind("SUPER + SHIFT + " .. item[1], hl.dsp.window.move({ direction = item[2] }), "移动窗口 " .. item[2])
end
for _, direction in ipairs({ "left", "down", "up", "right" }) do
	bind(
		"SUPER + CTRL + " .. direction,
		hl.dsp.window.move({ monitor = direction, follow = true }),
		"移到显示器 " .. direction
	)
end
for i = 1, 9 do
	bind("SUPER + " .. i, hl.dsp.focus({ workspace = i }), "工作区 " .. i)
	bind("SUPER + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }), "移动并跟随到 " .. i)
	bind("SUPER + CTRL + " .. i, hl.dsp.window.move({ workspace = i, follow = false }), "静默移动到 " .. i)
end
for _, item in ipairs({ { "Page_Down", "e+1" }, { "U", "e+1" }, { "Page_Up", "e-1" }, { "I", "e-1" } }) do
	bind("SUPER + " .. item[1], hl.dsp.focus({ workspace = item[2] }), "相邻工作区 " .. item[2])
end

-- on_created_empty is native and spawns into this workspace. Recalling an
-- existing workspace neither relaunches its tool nor resets user geometry.
for _, tool in ipairs({
	{
		name = "terminal",
		class = "mayon-scratch",
		keys = "SUPER + SHIFT + RETURN",
		command = desktop.commands.scratch,
		description = "临时终端",
		width = "0.78",
		height = "0.78",
	},
	{
		name = "files",
		class = "mayon-files",
		keys = "SUPER + ALT + E",
		command = desktop.commands.scratchFiles,
		description = "临时文件 Yazi",
		width = "0.78",
		height = "0.78",
	},
	{
		name = "monitor",
		class = "mayon-monitor",
		keys = "SUPER + ALT + M",
		command = desktop.commands.scratchMonitor,
		description = "系统监视 btop",
		width = "0.72",
		height = "0.74",
	},
}) do
	hl.workspace_rule({ workspace = "special:" .. tool.name, on_created_empty = tool.command })
	hl.window_rule({
		name = "tool-" .. tool.name,
		match = { class = "^" .. tool.class .. "$" },
		float = true,
		center = true,
		size = { "monitor_w*" .. tool.width, "monitor_h*" .. tool.height },
		animation = "fade",
	})
	bind(tool.keys, hl.dsp.workspace.toggle_special(tool.name), tool.description)
end

bind("SUPER + R", hl.dsp.submap("resize"), "调整大小模式（Esc 退出）")
hl.define_submap("resize", function()
	for _, item in ipairs({ { "H", -30, 0 }, { "J", 0, 30 }, { "K", 0, -30 }, { "L", 30, 0 } }) do
		hl.bind(item[1], hl.dsp.window.resize({ x = item[2], y = item[3], relative = true }), { repeating = true })
	end
	hl.bind("escape", hl.dsp.submap("reset"))
	hl.bind("RETURN", hl.dsp.submap("reset"))
end)
bind("SUPER + mouse:272", hl.dsp.window.drag(), "拖动窗口", { mouse = true })
bind("SUPER + mouse:273", hl.dsp.window.resize(), "调整窗口大小", { mouse = true })

for _, item in ipairs({
	{ "XF86AudioRaiseVolume", "volume-up", "提高音量" },
	{ "XF86AudioLowerVolume", "volume-down", "降低音量" },
	{ "XF86AudioMute", "volume-mute", "扬声器静音" },
	{ "XF86AudioMicMute", "mic-mute", "麦克风静音" },
	{ "XF86MonBrightnessUp", "brightness-up", "提高亮度" },
	{ "XF86MonBrightnessDown", "brightness-down", "降低亮度" },
}) do
	noctalia(item[1], item[2], item[3], { locked = true, repeating = not item[2]:match("mute") })
end
for key, action in pairs({
	XF86AudioPlay = "play-pause",
	XF86AudioStop = "stop",
	XF86AudioPrev = "previous",
	XF86AudioNext = "next",
}) do
	shell(key, desktop.commands.playerctl .. " " .. action, "媒体 " .. action, { locked = true })
end
for _, item in ipairs({
	{ "Print", "mark-shot" },
	{ "CTRL + Print", "screenshot-screen" },
	{ "SHIFT + Print", "wayscrollshot" },
	{ "SUPER + Print", "ocr-region" },
	{ "SUPER + SHIFT + Print", "ocr-screen" },
}) do
	shell(item[1], item[2], "截图/OCR " .. item[2])
end
bind("SUPER + F1", function()
	hl.exec_cmd(desktop.commands.help .. " " .. shell_quote(table.concat(help, "\n")))
end, "查看这份配置生成的键位帮助")
