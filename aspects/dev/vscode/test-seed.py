"""Regression fixtures for the mutable JSONC ownership boundary."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location('seed', Path(__file__).with_name('seed-settings.py'))
seed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(seed)
defaults_path = Path(sys.argv[1])
defaults = json.loads(defaults_path.read_text())

for text in [
    '{}\n',
    '\ufeff{"custom": "UTF-8 BOM"}\n',
    '// existing comment\n{\n "editor.fontSize": 19, // keep this\n "custom": "literal //,}",\n "workbench.colorCustomizations": {"editor.background": "#123456",},\n}\n',
    '{\r\n  /* 保留中文与 CRLF */ "editor.fontFamily": "custom",\r\n}\r\n',
    '{"workbench.colorCustomizations": null, "editor.tokenColorCustomizations": {"comments":"#abcdef"}}',
]:
    before, _ = seed.parse(text)
    after_text = seed.seed(text, defaults)
    after, _ = seed.parse(after_text)
    for key, value in before.items():
        if isinstance(value, dict):
            assert all(after[key][k] == v for k, v in value.items())
        else:
            assert after[key] == value
    assert seed.seed(after_text, defaults) == after_text
    if '// keep this' in text:
        assert '// keep this' in after_text and '"custom": "literal //,}"' in after_text
    if '\r\n' in text:
        assert '\n' not in after_text.replace('\r\n', '')

for bad in ['{"a":1,"a":2}', '{"a":', '[]', '{/* unfinished }']:
    try:
        seed.seed(bad, defaults)
    except ValueError:
        pass
    else:
        raise AssertionError('accepted malformed or ambiguous settings')

for empty in ['', '// 中文说明\n', '\ufeff/* 保留注释 */\r\n']:
    result = seed.seed(empty, defaults)
    assert result.startswith(empty)
    assert seed.parse(result)[0] == defaults
    assert seed.seed(result, defaults) == result

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / 'config'))
    target = root / 'config/Code/User/settings.json'
    command = [sys.executable, str(Path(__file__).with_name('seed-settings.py')), str(defaults_path)]
    subprocess.run(command, env=env, check=True)
    assert target.stat().st_mode & 0o777 == 0o600
    target.write_text('{"editor.fontSize": 21}')
    target.chmod(0o640)
    subprocess.run(command, env=env, check=True)
    assert json.loads(target.read_text())['editor.fontSize'] == 21
    assert target.stat().st_mode & 0o777 == 0o640
    before = target.read_bytes()
    target.parent.parent.joinpath('SingletonLock').symlink_to('private-host-12345')
    subprocess.run(command, env=env, check=True)
    assert target.read_bytes() == before
    target.parent.parent.joinpath('SingletonLock').unlink()
    lock = target.parent.parent / 'code.lock'
    lock.write_text(str(os.getpid()))
    target.write_text('{"editor.fontSize": 22}')
    before = target.read_bytes()
    subprocess.run(command, env=env, check=True)
    assert target.read_bytes() == before
    lock.write_text(str(10**30))
    subprocess.run(command, env=env, check=True)
    assert target.read_bytes() == before
    lock.write_text('999999999')
    subprocess.run(command, env=env, check=True)
    assert json.loads(target.read_text())['workbench.colorTheme'] == 'One Dark Pro'
    before = target.read_bytes()
    lock.unlink()
    target.rename(target.with_suffix('.saved'))
    target.symlink_to(target.with_suffix('.saved'))
    assert subprocess.run(command, env=env).returncode != 0
    assert target.read_bytes() == before
print('PASS: JSONC text, existing values, nested overrides, CRLF, idempotence, modes, locks, symlinks')
