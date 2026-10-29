"""Build an offline Luau pronunciation table, including heteronyms, from pypinyin."""

import json
import sys
from pathlib import Path

from pypinyin import Style, pinyin
from pypinyin.constants import PINYIN_DICT

lines = ["-- Generated at Nix build time from pypinyin; no runtime Python.", "return {"]
for codepoint in sorted(PINYIN_DICT):
    readings = pinyin(chr(codepoint), style=Style.NORMAL, heteronym=True)[0]
    readings = sorted({item.replace("ü", "v") for item in readings})
    if all(item.isascii() and item.isalpha() for item in readings):
        lines.append(f"\t[{codepoint}] = {json.dumps('/'.join(readings))},")
lines.append("}\n")
Path(sys.argv[1]).write_text("\n".join(lines))
