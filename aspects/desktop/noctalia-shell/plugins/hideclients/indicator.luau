-- Restores the mangobar `hideclients` module: an eye-off glyph plus the number
-- of hidden/minimized windows, hidden while the count is zero.
--
-- The two selectable sessions expose the state differently:
--   * Mango reports minimized clients per monitor as `hide_clients` over IPC
--     (`mmsg get all-monitors`); minimized clients live in its scratchpad pool.
--   * Umbriel reports every window over `umbriel windows --json`; minimized
--     windows carry `minimized = true`, and windows stashed in a scratchpad
--     carry a non-empty `scratchpad` name. A shown scratchpad marks its windows
--     visible, so only the hidden pool is counted.
-- Noctalia has no built-in counter widget; the built-in taskbar can show
-- per-window minimized badges instead, which is a different presentation.
--
-- @mmsg@, @umbriel@ and @mutedFg@ are substituted at build time by the Home
-- Manager module: absolute store paths avoid depending on the service PATH,
-- and the muted token keeps the repository's One Dark palette authoritative.
local MMSG = "@mmsg@"
local UMBRIEL = "@umbriel@"
local COLOR = "@mutedFg@"

-- Mango sets XDG_CURRENT_DESKTOP=mango; the Umbriel session sets
-- XDG_CURRENT_DESKTOP=Umbriel. Lowercase the value so both match. Any other
-- session keeps the widget hidden instead of spawning a tool with no socket.
local desktop = string.lower(noctalia.getenv("XDG_CURRENT_DESKTOP") or "")
local mangoSession = string.find(desktop, "mango", 1, true) ~= nil
local umbrielSession = string.find(desktop, "umbriel", 1, true) ~= nil
local minimized = 0
local stashed = 0
local busy = false

local function apply()
  local count = minimized + stashed
  if count <= 0 then
    barWidget.setVisible(false)
    return
  end
  barWidget.setGlyph("eye-off")
  barWidget.setText(tostring(count))
  barWidget.setTooltip({
    { key = "最小化", value = tostring(minimized) },
    { key = "临时隐藏", value = tostring(stashed) },
    { key = "恢复", value = "点击" },
  })
  barWidget.setVisible(true)
end

local function setCounts(nextMinimized, nextStashed)
  if nextMinimized == minimized and nextStashed == stashed then
    return
  end
  minimized = nextMinimized
  stashed = nextStashed
  apply()
end

local function pollMango()
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
    setCounts(total, 0)
  end)
end

local function pollUmbriel()
  noctalia.runAsync(UMBRIEL .. " windows --json", function(result)
    busy = false
    if not result or result.exitCode ~= 0 or type(result.stdout) ~= "string" then
      return
    end
    local windows = noctalia.json.decode(result.stdout)
    if type(windows) ~= "table" then
      return
    end
    local minimizedCount = 0
    local stashedCount = 0
    for _, window in ipairs(windows) do
      if type(window) == "table" then
        if window.minimized then
          minimizedCount = minimizedCount + 1
        elseif type(window.scratchpad) == "string" and window.scratchpad ~= "" and not window.visible then
          stashedCount = stashedCount + 1
        end
      end
    end
    setCounts(minimizedCount, stashedCount)
  end)
end

function update()
  if busy then
    return
  end
  if mangoSession then
    busy = true
    pollMango()
  elseif umbrielSession then
    busy = true
    pollUmbriel()
  end
end

function onClick()
  if mangoSession and (minimized + stashed) > 0 then
    -- Same verb as the Mango keybind: show a client from the minimized pool.
    noctalia.runAsync(MMSG .. " dispatch toggle_scratchpad")
  elseif umbrielSession then
    if stashed > 0 then
      noctalia.runAsync(UMBRIEL .. " msg scratchpad-toggle")
    elseif minimized > 0 then
      noctalia.runAsync(UMBRIEL .. " msg window-restore-minimized")
    end
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
