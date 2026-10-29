"""Build an offline Luau pronunciation table, including heteronyms, from pypinyin."""

import json
import sys
from pathlib import Path

from pypinyin import Style, pinyin
from pypinyin.constants import PINYIN_DICT

pages: dict[int, list[str]] = {}
for codepoint in sorted(PINYIN_DICT):
    readings = pinyin(chr(codepoint), style=Style.NORMAL, heteronym=True)[0]
    readings = sorted({item.replace("ü", "v") for item in readings})
    if all(item.isascii() and item.isalpha() for item in readings):
        page = codepoint // 256
        pages.setdefault(page, []).append(f"{codepoint}={'/'.join(readings)}")

# A Luau table literal with one AST entry per codepoint exceeds Noctalia's
# 100 ms plugin load budget. Store each 256-codepoint page as one escaped
# string and decode only the codepoints requested by the application index.
lines = ["-- Generated at Nix build time from pypinyin; no runtime Python.", "local pages = {"]
for page, entries in sorted(pages.items()):
    lines.append(f"\t[{page}] = {json.dumps(';' + ';'.join(entries) + ';')},")
lines.extend(
    [
        "}",
        "local readings = {}",
        "return setmetatable(readings, {",
        "\t__index = function(cache, codepoint)",
        "\t\tif type(codepoint) ~= \"number\" then",
        "\t\t\treturn nil",
        "\t\tend",
        "\t\tlocal page = pages[math.floor(codepoint / 256)]",
        "\t\tif not page then",
        "\t\t\treturn nil",
        "\t\tend",
        "\t\tlocal _, start = string.find(page, \";\" .. codepoint .. \"=\", 1, true)",
        "\t\tlocal value",
        "\t\tif start then",
        "\t\t\tlocal stop = string.find(page, \";\", start + 1, true)",
        "\t\t\tvalue = string.sub(page, start + 1, stop - 1)",
        "\t\tend",
        "\t\tif value then",
        "\t\t\trawset(cache, codepoint, value)",
        "\t\tend",
        "\t\treturn value",
        "\tend",
        "})",
        "",
    ]
)
Path(sys.argv[1]).write_text("\n".join(lines))
