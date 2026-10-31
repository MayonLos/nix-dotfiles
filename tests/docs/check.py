#!/usr/bin/env python3
"""Keep docs/ indexable: front matter, routing table entries and local links."""
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
docs = root / "docs"
errors = []
index = (docs / "README.md").read_text()
keys = ("summary", "read_when", "code", "checks")

for doc in sorted(docs.glob("*.md")):
    text = doc.read_text()
    match = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not match:
        errors.append(f"{doc.name}: missing front matter")
        continue
    fields = dict(
        line.split(": ", 1) for line in match.group(1).splitlines() if ": " in line
    )
    for key in keys:
        if key not in fields:
            errors.append(f"{doc.name}: missing {key}")
    for path in re.findall(r"[^\[\], ]+", fields.get("code", "")):
        # Local work state such as .work/ is intentionally not in the flake source.
        if not path.startswith(".work/") and not (root / path).exists():
            errors.append(f"{doc.name}: code path does not exist: {path}")
    if doc.name != "README.md" and f"]({doc.name})" not in index:
        errors.append(f"{doc.name}: not in the docs/README.md routing table")

sources = [root / "AGENTS.md", root / "README.md", *docs.glob("*.md")]
for source in sources:
    for target in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", source.read_text()):
        if re.match(r"[a-z]+:", target):
            continue
        if not (source.parent / target).exists():
            errors.append(f"{source.relative_to(root)}: broken link: {target}")

if errors:
    sys.exit("\n".join(errors))
