"""Compare the export against Mango's rendered config, not another bind list."""
import collections
import json
import re
import sys
from pathlib import Path


def rendered_rows(text):
    mode = "default"
    rows = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, raw = (part.strip() for part in line.split("=", 1))
        if key == "key_mode":
            mode = raw
        elif re.fullmatch(r"(?:bind[a-z]*|mousebind[a-z]*|gesturebind[a-z]*)", key):
            rows.append((mode, key, raw))
    return rows


def check(data_path, mango_path, listed_path):
    data = json.loads(Path(data_path).read_text())
    assert data["version"] == 1
    exported = [(row["mode"], row["kind"], row["raw"]) for row in data["bindings"]]
    actual = rendered_rows(Path(mango_path).read_text())
    assert collections.Counter(exported) == collections.Counter(actual), (
        "Mango/export mismatch",
        collections.Counter(actual) - collections.Counter(exported),
        collections.Counter(exported) - collections.Counter(actual),
    )
    listed = json.loads(Path(listed_path).read_text())
    assert collections.Counter((row["mode"], row["kind"], row["raw"]) for row in listed) == collections.Counter(actual)
    assert all(row["chord"] and row["description"] for row in listed)
    assert {row["group"] for row in listed} == {"窗口", "工作区", "应用", "TUI 工具", "截图", "媒体", "系统"}
    assert any(row[0] == "resize" for row in actual)
    assert any(row[0] == "common" for row in actual)
    assert any(row[1] == "mousebind" for row in actual)
    assert any(row[1] == "gesturebind" for row in actual)
    print(f"PASS: {len(actual)} bindings exactly match rendered Mango config and CLI output")


if __name__ == "__main__":
    check(*sys.argv[1:])
