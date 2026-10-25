local generationNumber = require("../generation_number")

assert(generationNumber.fromMatchingLinks("system-7-link\nsystem-12-link\n") == "12")
assert(generationNumber.fromMatchingLinks("system-7-link\nsystem-12-link\nsystem-9-link\n") == "12")
assert(generationNumber.fromMatchingLinks("system-link\nnot-a-system-22-link\n") == nil)
assert(generationNumber.fromMatchingLinks("") == nil)
assert(generationNumber.statusText("419", "updates", "current", "current") == "419↻")
assert(generationNumber.statusText("419", "current", "different", "different") == "419↺✓⇧")
assert(generationNumber.statusText(nil, "current", "checking", "checking") == "✓")
assert(generationNumber.statusText("419", "error", "current", "current") == "419!")
assert(generationNumber.statusText("419", "unconfigured", "current", "disabled") == "419·")

print("nix-status generation number tests passed")
