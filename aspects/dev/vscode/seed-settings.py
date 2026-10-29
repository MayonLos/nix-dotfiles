"""Seed missing VS Code JSONC keys without rewriting user text or values."""

import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


# Replace comments and trailing commas with spaces, preserving source offsets.
LEX = re.compile(r'"(?:[^"\\]|\\.)*"|//[^\r\n]*|/\*[\s\S]*?\*/')


def clean_jsonc(text):
    def clean(match):
        value = match.group()
        return value if value.startswith('"') else re.sub(r'[^\r\n]', ' ', value)

    clean = LEX.sub(clean, text)
    if clean.startswith('\ufeff'):
        clean = ' ' + clean[1:]
    return clean


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def parse(text):
    clean = clean_jsonc(text)
    # Tokenize strings so commas inside strings are never interpreted as JSON.
    clean = re.sub(
        r'"(?:[^"\\]|\\.)*"|,(?=\s*[}\]])',
        lambda m: ' ' if m.group() == ',' else m.group(),
        clean,
    )
    value = json.loads(clean, object_pairs_hook=unique)
    if not isinstance(value, dict):
        raise ValueError("settings root must be an object")
    return value, clean


def members(clean, start=0):
    """Return value spans and closing brace for one validated JSON object."""
    decoder = json.JSONDecoder()
    index = start + 1
    result = {}
    while True:
        while clean[index].isspace() or clean[index] == ',':
            index += 1
        if clean[index] == '}':
            return result, index
        key, index = decoder.raw_decode(clean, index)
        while clean[index].isspace() or clean[index] == ':':
            index += 1
        begin = index
        _, index = decoder.raw_decode(clean, index)
        result[key] = (begin, index)


def insert(text, additions, start=0, indent='  '):
    _, clean = parse(text)
    entries, close = members(clean, start)
    if not additions:
        return text
    raw_clean = clean_jsonc(text)
    comma = ',' if entries and not raw_clean[:close].rstrip().endswith(',') else ''
    newline = '\r\n' if '\r\n' in text else '\n'
    rendered = []
    for key, value in additions.items():
        lines = (json.dumps(key, ensure_ascii=False) + ': ' + json.dumps(value, ensure_ascii=False, indent=2)).splitlines()
        rendered.append(newline.join(indent + line for line in lines))
    block = comma + newline + (',' + newline).join(rendered) + newline + indent[:-2]
    return text[:close] + block + text[close:]


def seed(text, defaults):
    if not clean_jsonc(text).strip():
        newline = '\r\n' if '\r\n' in text else '\n'
        text += newline + '{}' + newline
    value, clean = parse(text)
    root = clean.index('{')
    # Nested customization dictionaries keep each existing leaf/theme override.
    for key in ('workbench.colorCustomizations', 'editor.tokenColorCustomizations'):
        if isinstance(value.get(key), dict):
            spans, _ = members(clean, root)
            missing = {k: v for k, v in defaults[key].items() if k not in value[key]}
            text = insert(text, missing, spans[key][0], '    ')
            value, clean = parse(text)
    return insert(text, {k: v for k, v in defaults.items() if k not in value}, root)


def safe_path(path):
    for part in [path, *path.parents]:
        if part.is_symlink():
            raise ValueError(f"refusing symlink: {part}")


def profile_locked(profile):
    if os.path.lexists(profile / 'SingletonLock'):
        return True
    lock = profile / 'code.lock'
    if lock.is_symlink():
        return True
    try:
        pid = int(lock.read_text(encoding='ascii').strip())
        if pid <= 0:
            return True
    except FileNotFoundError:
        return False
    except (ValueError, OSError):
        return True
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except (PermissionError, OverflowError):
        return True
    # Recycled live PIDs conservatively defer seeding to a later activation.
    return True


def main():
    defaults = json.loads(Path(sys.argv[1]).read_text())
    config = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config')))
    target = config / 'Code/User/settings.json'
    safe_path(target)
    # An active or stale profile lock needs a later activation with Code closed.
    if profile_locked(config / 'Code'):
        print('VS Code profile is locked; leaving settings unchanged', file=sys.stderr)
        return
    original = target.read_bytes() if target.exists() else None
    text = original.decode('utf-8') if original is not None else '{}\n'
    updated = seed(text, defaults).encode('utf-8')
    if updated == original:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    safe_path(target)
    mode = stat.S_IMODE(target.stat().st_mode) if original is not None else 0o600
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix='.settings-seed-', delete=False) as stream:
            temporary = stream.name
            os.fchmod(stream.fileno(), mode)
            stream.write(updated)
            stream.flush()
            os.fsync(stream.fileno())
        safe_path(target)
        current = target.read_bytes() if target.exists() else None
        if current != original:
            raise ValueError('settings changed concurrently; leaving them unchanged')
        if profile_locked(config / 'Code'):
            print('VS Code started during seed; leaving settings unchanged', file=sys.stderr)
            return
        os.replace(temporary, target)
        temporary = None
    finally:
        if temporary is not None:
            os.unlink(temporary)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        sys.exit(f'VS Code settings seed: {error}')
