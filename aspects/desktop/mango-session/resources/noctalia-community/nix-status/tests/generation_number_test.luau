local generationNumber = require("../generation_number")

assert(generationNumber.fromMatchingLinks("system-7-link\nsystem-12-link\n") == "12")
assert(generationNumber.fromMatchingLinks("system-7-link\nsystem-12-link\nsystem-9-link\n") == "12")
assert(generationNumber.fromMatchingLinks("system-link\nnot-a-system-22-link\n") == nil)
assert(generationNumber.fromMatchingLinks("") == nil)

print("nix-status generation number tests passed")
