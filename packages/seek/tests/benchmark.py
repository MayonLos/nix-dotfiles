#!/usr/bin/env python3
"""Run retrieval QA against an explicitly supplied synthetic corpus only."""
import argparse
import json
import os
import subprocess
import time
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--binary', required=True)
p.add_argument('--root', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--lexical', action='store_true')
a = p.parse_args()
binary = str(Path(a.binary).resolve())
root = a.root.resolve()
# Dedicated fixture HOME, never the real user's configuration or index.
home = a.output.parent / ('bench-lexical' if a.lexical else 'bench-hybrid')
home.mkdir(parents=True, exist_ok=True)
env = {'HOME': str(home), 'XDG_CONFIG_HOME': str(home / '.config'),
       'XDG_DATA_HOME': str(home / '.local/share'), 'PATH': os.defpath,
       'LANG': 'C.UTF-8'}
# Copy only explicit runtime dependencies, never the inherited environment.
for tool in ['pdftotext']:
    import shutil
    found = shutil.which(tool)
    if found:
        env['PATH'] = str(Path(found).parent) + ':' + env['PATH']
if os.environ.get('SEEK_TEST_ORT'):
    env['ORT_DYLIB_PATH'] = os.environ['SEEK_TEST_ORT']
config = home / '.config/seek/config.toml'
config.parent.mkdir(parents=True, exist_ok=True)
config.write_text('confirmed = true\ninclude = [' + json.dumps(str(root)) + ']\n'
                  'exclude = ["**/benchmark.json"]\nembeddings = ' +
                  ('false' if a.lexical else 'true') + '\n', encoding='utf-8')
config.chmod(0o600)

def run(*args):
    return subprocess.run([binary, *args], env=env, check=True, capture_output=True, text=True).stdout

if not a.lexical:
    run('model', 'download')
indexed = json.loads(run('index'))
cases = json.loads((root / 'benchmark.json').read_text())
rows = []
started = time.perf_counter()
process = subprocess.run([binary, 'batch', '--limit', '5'],
                         input=''.join(c['question'] + '\n' for c in cases),
                         env=env, check=True, capture_output=True, text=True)
responses = [json.loads(line) for line in process.stdout.splitlines()]
for case, response in zip(cases, responses, strict=True):
    names = [Path(h['path']).name for h in response['hits']]
    rows.append({**case, 'hit_at_5': case['expected'] in names, 'results': names,
                 'warm_query_ms': round(response['elapsed_ms'], 2)})
report = {'mode': 'lexical' if a.lexical else 'hybrid', 'index': indexed,
          'batch_total_ms': round((time.perf_counter() - started) * 1000, 2),
          'questions': len(rows), 'hits_at_5': sum(r['hit_at_5'] for r in rows),
          'hit_rate_at_5': sum(r['hit_at_5'] for r in rows) / len(rows), 'cases': rows}
a.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k != 'cases'}, ensure_ascii=False))
if a.lexical and report['hit_rate_at_5'] < 0.65:
    raise SystemExit('lexical retrieval regression: hit@5 below 65%')
