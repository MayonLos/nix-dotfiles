"""Rewrites bindings.json from mango.conf with the parser check_bindings.py uses."""
import json
import re
from pathlib import Path

here = Path(__file__).parent
mode = "default"
rows = []
for line in (here / "mango.conf").read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, raw = (part.strip() for part in line.split("=", 1))
    if key == "key_mode":
        mode = raw
    elif re.fullmatch(r"(?:bind[a-z]*|mousebind[a-z]*|gesturebind[a-z]*)", key):
        rows.append({"mode": mode, "kind": key, "raw": raw})
text = json.dumps({"version": 1, "bindings": rows}, ensure_ascii=False, indent=1)
(here / "bindings.json").write_text(text + "\n")
