--!nonstrict
-- Port count follows panel filtering while keeping the launcher readable.

local countLabel = require("./count_label.luau")
local visibleCount = nil

local function applyCount(n)
    local count = tonumber(n) or 0
    barWidget.setVisible(count > 0)
    barWidget.setGlyph(noctalia.getConfig("glyph") or "plug")
    barWidget.setText(countLabel.format(count))
    barWidget.setTooltip({ { key = "监听端口", value = countLabel.format(count) } })
end

noctalia.state.watch("portctl_visible_count", function(n)
    visibleCount = n
    applyCount(n or 0)
end)

noctalia.state.watch("portctl_stats", function(stats)
    if visibleCount ~= nil then
        return
    end
    local n = (stats and stats.count_tcp) or (stats and stats.count) or 0
    applyCount(n)
end)

local count = noctalia.state.get("portctl_visible_count")
if count ~= nil then
    visibleCount = count
else
    local stats = noctalia.state.get("portctl_stats")
    count = (stats and stats.count_tcp) or (stats and stats.count) or 0
end
applyCount(count)

function onClick()
    noctalia.togglePanel("rxtsel/portctl:panel")
end
