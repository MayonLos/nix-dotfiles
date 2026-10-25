local function shouldShow(showCountSetting: boolean, runningCount: number): boolean
    return showCountSetting and runningCount > 0
end

return {
    shouldShow = shouldShow,
}
