#!/usr/bin/env python3
"""Optional DeepSeek cleanup helper; every failure returns the original text."""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

ENDPOINT = "https://api.deepseek.com/chat/completions"


def polish(text: str, key_file: str, hotwords: list[str] | None = None) -> str:
    original = text
    try:
        key_path = Path(key_file).expanduser()
        key = key_path.read_text(encoding="utf-8").strip()
        if not key:
            return original
        terms = [str(term) for term in (hotwords or []) if str(term).strip()]
        system = (
            "你负责轻量整理中文语音识别结果。只删除口头填充词、修正明显标点和常见术语；"
            "保留原意、语气、英文技术名词，不补充事实。只输出整理后的文本。"
        )
        if terms:
            system += " 术语请优先采用这些写法：" + "、".join(terms[:100])
        body = json.dumps({
            "model": "deepseek-chat",
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": text},
            ],
            "temperature": 0.1,
            "max_tokens": max(128, min(2048, len(text) * 3)),
            "stream": False,
        }).encode("utf-8")
        request = urllib.request.Request(
            ENDPOINT,
            data=body,
            headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=3) as response:
            payload = json.loads(response.read())
        value = payload["choices"][0]["message"]["content"].strip()
        return value or original
    except (OSError, ValueError, KeyError, IndexError, TypeError, urllib.error.URLError):
        return original


def main() -> int:
    for line in sys.stdin:
        try:
            request = json.loads(line)
            text = request.get("text", "")
            if not isinstance(text, str):
                raise ValueError("text must be a string")
            result = polish(text, str(request.get("key_file", "")), request.get("hotwords"))
            print(json.dumps({"text": result}, ensure_ascii=False), flush=True)
        except Exception:
            print(json.dumps({"text": ""}, ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
