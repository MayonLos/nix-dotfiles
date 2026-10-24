--!nonstrict
-- The command is installed by the hardware feature and only reads/writes the
-- already-authorized conservation_mode sysfs node. Polling stays asynchronous.

local active = false
local busy = false
local activeColor = noctalia.getConfig("active_color")

local function render()
  barWidget.setVisible(active)
  barWidget.setGlyph("")
  barWidget.setGlyphColor(activeColor)
  barWidget.setColor(activeColor)
  barWidget.setText(active and "养护" or "")
  barWidget.setTooltip(active and "电池养护模式已开启 · 点击关闭" or "电池养护模式 · 点击开启")
end

local function readStatus()
  if busy then return end
  busy = true
  local started = noctalia.runAsync({ "legion-conservation", "status" }, function(result)
    busy = false
    active = result.exitCode == 0 and string.match(result.stdout or "", "^%s*养护%s*$") ~= nil
    render()
  end, 1000)
  if not started then busy = false end
end

function update()
  noctalia.setUpdateInterval(5000)
  activeColor = noctalia.getConfig("active_color")
  readStatus()
end

function onClick()
  if busy then return end
  busy = true
  local started = noctalia.runAsync({ "legion-conservation", "toggle" }, function(result)
    busy = false
    if result.exitCode ~= 0 then
      noctalia.notify("电池养护模式", "切换失败")
    end
    readStatus()
  end, 3000)
  if not started then busy = false end
end
