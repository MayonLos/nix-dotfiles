-- Restores the `hideclients` module the mangobar bar had: an eye-off glyph
-- plus the number of minimized windows, hidden while nothing is minimized.
--
-- Mango keeps minimized clients in its scratchpad pool and publishes the
-- per-monitor count as `hide_clients` over IPC, so `mmsg get all-monitors` is
-- the only source. Noctalia has no built-in counter widget; the built-in
-- taskbar can show per-window minimized badges instead, which is a different
-- presentation.
--
-- @mmsg@ and @mutedFg@ are substituted at build time by the Home Manager
-- module: an absolute store path avoids depending on the service PATH, and the
-- muted token keeps the repository's One Dark palette authoritative.
local MMSG = "@mmsg@"
local COLOR = "@mutedFg@"

-- Mango exports XDG_CURRENT_DESKTOP=mango. Umbriel and Hyprland have no
-- `hide_clients` IPC, so the widget stays hidden there instead of spawning a
-- tool that would fail on a missing socket.
local mangoSession = noctalia.getenv("XDG_CURRENT_DESKTOP") == "mango"
local count = 0
local busy = false

local function apply()
  if count <= 0 then
    barWidget.setVisible(false)
    return
  end
  barWidget.setGlyph("eye-off")
  barWidget.setText(tostring(count))
  barWidget.setTooltip({
    { key = "最小化窗口", value = tostring(count) },
    { key = "恢复最近一个", value = "点击" },
  })
  barWidget.setVisible(true)
end

function update()
  if not mangoSession or busy then
    return
  end
  busy = true
  noctalia.runAsync(MMSG .. " get all-monitors", function(result)
    busy = false
    if not result or result.exitCode ~= 0 or type(result.stdout) ~= "string" then
      return
    end
    local data = noctalia.json.decode(result.stdout)
    if type(data) ~= "table" or type(data.monitors) ~= "table" then
      return
    end
    local total = 0
    for _, monitor in ipairs(data.monitors) do
      total = total + (tonumber(monitor.hide_clients) or 0)
    end
    if total ~= count then
      count = total
      apply()
    end
  end)
end

function onClick()
  if count > 0 then
    -- Same verb as the Mango keybind: show a client from the minimized pool.
    noctalia.runAsync(MMSG .. " dispatch toggle_scratchpad")
  end
end

function onExit()
  barWidget.setVisible(false)
end

barWidget.setColor(COLOR)
barWidget.setGlyphColor(COLOR)
barWidget.setVisible(false)
noctalia.setUpdateInterval(1000)
apply()
