-- Select the newest profile generation whose resolved target is the active system.
-- The command output consists only of matching `system-N-link` basenames.
local function fromMatchingLinks(output: string): string?
    local newestNumber: number? = nil
    local newestLabel: string? = nil

    for link in output:gmatch("[^\r\n]+") do
        local digits = link:match("^system%-(%d+)%-link$")
        local number = if digits ~= nil then tonumber(digits) else nil
        if number ~= nil and (newestNumber == nil or number > newestNumber) then
            newestNumber = number
            newestLabel = digits
        end
    end

    return newestLabel
end

local function statusText(generation: string?): string
    return generation or ""
end

local function hasInputUpdates(updateState: string): boolean
    return updateState == "updates"
end

return {
    fromMatchingLinks = fromMatchingLinks,
    statusText = statusText,
    hasInputUpdates = hasInputUpdates,
}
