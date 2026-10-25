local function format(count: number): string
    local value = math.max(0, math.floor(tonumber(count) or 0))
    return tostring(value) .. (value == 1 and " port" or " ports")
end

return {
    format = format,
}
