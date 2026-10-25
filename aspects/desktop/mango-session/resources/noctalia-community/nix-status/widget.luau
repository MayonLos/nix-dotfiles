local contracts = require("./lib/contracts.luau")
local generationNumberHelper = require("./generation_number.luau")

type UpdateStatus = contracts.UpdateStatus
type GenerationStatus = contracts.GenerationStatus
type SystemTargetStatus = contracts.SystemTargetStatus


local updateStatus: UpdateStatus? = noctalia.state.get(contracts.state.updateStatus)
local generationStatus: GenerationStatus? = noctalia.state.get(contracts.state.generationStatus)
local systemTargetStatus: SystemTargetStatus? = noctalia.state.get(contracts.state.systemTargetStatus)
local currentGenerationNumber: string? = nil
local generationLookupRunning = false

local generationNumberCommand = [[
current_system="$(readlink -f /run/current-system 2>/dev/null)" || exit 1
# Prefer the selected profile when it names the active closure, including rollback
# to an earlier profile with the same closure. Otherwise (e.g. test activation),
# match the running closure against retained generations without changing it.
selected_profile="$(readlink /nix/var/nix/profiles/system 2>/dev/null)" || selected_profile=""
if [ "$(readlink -f /nix/var/nix/profiles/system 2>/dev/null)" = "$current_system" ]; then
    printf '%s\n' "${selected_profile##*/}"
    exit 0
fi
for profile in /nix/var/nix/profiles/system-*-link; do
    [ -L "$profile" ] || continue
    profile_system="$(readlink -f "$profile" 2>/dev/null)" || continue
    if [ "$profile_system" = "$current_system" ]; then
        printf '%s\n' "${profile##*/}"
    fi
done
]]

local show: () -> ()

local function refreshCurrentGenerationNumber()
    if generationLookupRunning then
        return
    end

    generationLookupRunning = true
    local started = noctalia.runAsync(generationNumberCommand, function(result)
        generationLookupRunning = false
        currentGenerationNumber = nil
        if result ~= nil and result.exitCode == 0 then
            currentGenerationNumber = generationNumberHelper.fromMatchingLinks(result.stdout or "")
        end
        show()
    end, 5000)
    if not started then
        generationLookupRunning = false
    end
end

show = function()
    local updateState = updateStatus and updateStatus.state or "idle"
    local generationState = generationStatus and generationStatus.state or "checking"
    local systemTargetState = systemTargetStatus and systemTargetStatus.state or "checking"

    -- Keep the snowflake and generation number compact; update state lives in
    -- the tooltip and a layout-free badge.
    barWidget.setGlyph("snowflake")
    barWidget.setGlyphColor("primary", "script")
    barWidget.setText(generationNumberHelper.statusText(currentGenerationNumber))
    barWidget.setBadge(generationNumberHelper.hasInputUpdates(updateState))

    local tooltip = { "NixOS" }
    if currentGenerationNumber ~= nil then
        table.insert(tooltip, "generation " .. currentGenerationNumber)
    end

    if generationState == "current" then
        table.insert(tooltip, "booted generation is current")
    elseif generationState == "different" then
        table.insert(tooltip, "booted generation differs")
    elseif generationState == "checking" then
        table.insert(tooltip, "checking generation…")
    elseif generationState == "error" then
        table.insert(tooltip, "generation check failed")
    end

    if systemTargetState == "current" then
        table.insert(tooltip, "configured system is active")
    elseif systemTargetState == "different" then
        table.insert(tooltip, "switch available")
    elseif systemTargetState == "checking" then
        table.insert(tooltip, "checking configured system…")
    elseif systemTargetState == "error" then
        table.insert(tooltip, "configuration check failed")
    elseif systemTargetState == "disabled" then
        table.insert(tooltip, "configuration check not configured")
    end

    if updateState == "current" then
        table.insert(tooltip, "inputs up to date")
    elseif updateState == "updates" then
        table.insert(tooltip, "inputs updated")
    elseif updateState == "unconfigured" then
        table.insert(tooltip, "flake updates not configured")
    elseif updateState == "checking" then
        table.insert(tooltip, "updating inputs…")
    elseif updateState == "error" then
        table.insert(tooltip, "input update failed")
    end

    barWidget.setTooltip(table.concat(tooltip, " · "))
end

function update()
    -- State watches handle service changes; avoid a profile walk every bar tick.
    noctalia.setUpdateInterval(30000)
    updateStatus = noctalia.state.get(contracts.state.updateStatus)
    generationStatus = noctalia.state.get(contracts.state.generationStatus)
    systemTargetStatus = noctalia.state.get(contracts.state.systemTargetStatus)
    barWidget.setMinWidth(28)
    show()
    refreshCurrentGenerationNumber()
end

noctalia.state.watch(contracts.state.updateStatus, function(status)
    updateStatus = status
    show()
end)

noctalia.state.watch(contracts.state.generationStatus, function(status)
    generationStatus = status
    show()
    refreshCurrentGenerationNumber()
end)

noctalia.state.watch(contracts.state.systemTargetStatus, function(status)
    systemTargetStatus = status
    show()
end)

function onClick()
    noctalia.togglePanel("mindnbytes/nix-status:details")
end
