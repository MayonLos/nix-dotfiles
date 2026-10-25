local countLabel = require("../count_label")

assert(countLabel.format(11) == "11 ports")
assert(countLabel.format(1) == "1 port")
assert(countLabel.format(0) == "0 ports")
assert(countLabel.format(-4) == "0 ports")

print("portctl count label tests passed")
