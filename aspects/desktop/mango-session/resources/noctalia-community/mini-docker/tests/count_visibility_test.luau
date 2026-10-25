local countVisibility = require("../count_visibility")

assert(not countVisibility.shouldShow(true, 0))
assert(countVisibility.shouldShow(true, 1))
assert(countVisibility.shouldShow(true, 3))
assert(not countVisibility.shouldShow(false, 3))

print("mini-docker count visibility tests passed")
