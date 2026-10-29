"""Put uosc 5.12's native seek/controls on one optional hover rail.

Geometry and subtitle clearance change; native seek, thumbnail, chapter, button
and menu handlers stay intact. Every anchor is checked so upgrades fail visibly.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1])


def replace(file, old, new):
    path = root / file
    text = path.read_text()
    if text.count(old) != 1:
        raise RuntimeError(f"uosc compact rail anchor changed: {file}: {old!r}")
    path.write_text(text.replace(old, new))


replace("main.lua", "\ttimeline_style = 'line',", "\tcompact_rail = false,\n\ttimeline_style = 'line',")
replace(
    "elements/Controls.lua",
    "return Elements:v('speed', 'dragging') and 1 or Elements:maybe('timeline', 'get_is_hovered')",
    "return Elements:v('speed', 'dragging') and 1 or (not options.compact_rail and Elements:maybe('timeline', 'get_is_hovered'))",
)
replace(
    "elements/Controls.lua",
    "self.by = Elements:v('timeline', 'ay', display.height - window_border) - margin",
    "self.by = (options.compact_rail and (display.height - window_border)\n\t\tor Elements:v('timeline', 'ay', display.height - window_border)) - margin",
)
replace(
    "elements/Timeline.lua",
    "\tself.width = self.bx - self.ax",
    """\tif options.compact_rail then
		local margin = round(options.controls_margin * state.scale)
		local button = round(options.controls_size * state.scale)
		local spacing = round(options.controls_spacing * state.scale)
		local timestamp_opts = {size = self.font_size}
		local elapsed_width = math.max(64 * state.scale,
			timestamp_width(state.time_human or '00:00', timestamp_opts) + 2 * spacing)
		local remaining_width = math.max(64 * state.scale,
			timestamp_width(state.destination_time_human or '-00:00', timestamp_opts) + 2 * spacing)
		-- Match play-pause,space,menu,fullscreen, reserving time on each end.
		self.ax = window_border_size + margin + button + spacing + elapsed_width
		self.bx = display.width - window_border_size - margin - 2 * (button + spacing) - remaining_width
		self.by = display.height - window_border_size - margin
		self.ay = self.by - self.size
	end
	self.width = self.bx - self.ax""",
)
replace(
    "elements/Timeline.lua",
    "function Timeline:get_time_at_x(x)\n",
    """function Timeline:get_time_at_x(x)
	if options.compact_rail then
		return state.duration * clamp(0, (x - self.ax) / self.width, 1)
	end
""",
)
replace(
    "elements/Timeline.lua",
    "\t-- Progress\n\tlocal function draw_progress()",
    """\t-- One background for the native timeline and native buttons.
	if options.compact_rail then
		local margin = round(options.controls_margin * state.scale)
		ass:rect(margin - 6 * state.scale, self.by - self.size - 4 * state.scale,
			display.width - margin + 6 * state.scale, self.by + 4 * state.scale,
			{color = bg, opacity = visibility * 0.94, radius = state.radius})
	end

	-- Progress
	local function draw_progress()""",
)
replace(
    "elements/Timeline.lua",
    "\t\tass:rect(fax, fay, fbx, fby, {opacity = config.opacity.position})",
    """\t	if options.compact_rail then
			local half = self.line_width / 2
			local x = bax + self.width * progress
			ass:rect(bax, fcy - half, bbx, fcy + half,
				{color = config.color.selection or bg, opacity = visibility})
			ass:rect(bax, fcy - half, x, fcy + half,
				{color = config.color.match, opacity = visibility})
			ass:rect(x - half, fcy - half * 2, x + half, fcy + half * 2,
				{color = bgt, opacity = visibility, radius = half})
		else
			ass:rect(fax, fay, fbx, fby, {opacity = config.opacity.position})
		end""",
)
replace(
    "elements/Timeline.lua",
    "\tlocal function draw_timeline_timestamp(x, y, align, timestamp, opts)\n",
    """\tlocal function draw_timeline_timestamp(x, y, align, timestamp, opts)
		if options.compact_rail then
			opts.color, opts.border_color = bgt, bg
			ass:txt(x, y, align, timestamp, opts)
			return
		end
""",
)
replace(
    "elements/Timeline.lua",
    "draw_timeline_timestamp(bax + spacing, fcy, 4, state.time_human, time_opts)",
    """draw_timeline_timestamp(options.compact_rail and (bax - spacing) or (bax + spacing),
				fcy, options.compact_rail and 6 or 4, state.time_human, time_opts)""",
)
replace(
    "elements/Timeline.lua",
    "draw_timeline_timestamp(bbx - spacing, fcy, 6, state.destination_time_human, time_opts)",
    """draw_timeline_timestamp(options.compact_rail and (bbx + spacing) or (bbx - spacing),
				fcy, options.compact_rail and 4 or 6, state.destination_time_human, time_opts)""",
)
# The compact rail is hidden as a unit. Keep the native expanded timeline in
# default mode; suppress its tall background, chapter diamonds and cursor line
# only in compact mode (chapter navigation remains in the menu).
replace("elements/Timeline.lua", "ass:opacity(config.opacity.timeline)", "ass:opacity(options.compact_rail and 0 or config.opacity.timeline)")
replace("elements/Timeline.lua", "\t\tif diamond_radius > 0 then", "\t\tif diamond_radius > 0 and not options.compact_rail then")
replace("elements/Timeline.lua", "ass:rect(ax, ay, bx, by, {color = color, opacity = 0.33})", "ass:rect(ax, ay, bx, by, {color = color, opacity = options.compact_rail and 0 or 0.33})")

replace("elements/Timeline.lua", "self.obstructed = available_space < self.size + 10", "self.obstructed = available_space < self.size + 10 or (options.compact_rail and self.width < 64 * state.scale)")

replace("elements/Timeline.lua", "function Timeline:on_prop_time() self:decide_enabled() end", "function Timeline:on_prop_time()\n\tif options.compact_rail then self:update_dimensions() else self:decide_enabled() end\nend")


# Run before render's unchanged-OSD shortcut: live subtitle settings may change
# without changing any ASS control text, and hover is not a persistent margin.
replace("lib/utils.lua", "\t-- submit\n", "\tupdate_compact_subtitles()\n\n\t-- submit\n")
replace(
    "main.lua",
    "function update_margins()",
    """local compact_subtitles = require('lib/compact-subtitles')(mp)
mp.observe_property('sub-margin-y', 'number', function() request_render() end)
mp.observe_property('sub-align-y', 'string', function() request_render() end)

function update_compact_subtitles()
	local controls, timeline = Elements.controls, Elements.timeline
	local visibility = math.max(controls and controls.enabled and controls:get_visibility() or 0,
		timeline and timeline.enabled and timeline:get_visibility() or 0)
	local required = 0
	if options.compact_rail and state.path and state.is_video and controls and controls.enabled
		and visibility > 0 and display.height > 0 and mp.get_property('sub-align-y') == 'bottom' then
		-- Background extends 4px above controls. Leave 8px above that edge.
		required = (display.height - controls.ay + 12 * state.scale) * 720 / display.height
	end
	compact_subtitles.update(required)
end

function update_margins()""",
)
