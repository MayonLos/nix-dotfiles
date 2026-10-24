"""Cold-process Lua LSP comparison. All writable state stays inside the checkout.
Usage: python3 run.py NVIM LUA_LANGUAGE_SERVER EMMYLUA_LS OUTPUT_DIRECTORY
No OS page-cache flush is attempted. Peak RSS sums nvim and all descendants,
polled from /proc every 10ms; server-only RSS is also retained.
"""
import json
import os
import math
from pathlib import Path
import statistics
import subprocess
import sys
import time

repo = Path(__file__).resolve().parents[4]
nvim, luals, emmy, output = sys.argv[1:]
output = Path(output).resolve()
output.mkdir(parents=True, exist_ok=False)
workspace = repo / 'aspects/editing/neovim/config'
state = repo / '.team/r10' / (output.name + '-state')
state.mkdir(parents=True, exist_ok=False)


def memory(pid):
    total = 0
    processes = {}
    todo = [pid]
    while todo:
        current = todo.pop()
        try:
            status = Path(f'/proc/{current}/status').read_text().splitlines()
            rss = next((int(s.split()[1]) for s in status if s.startswith('VmRSS:')), 0)
            processes[current] = rss
            total += rss
            todo.extend(map(int, Path(f'/proc/{current}/task/{current}/children').read_text().split()))
        except (FileNotFoundError, ProcessLookupError):
            pass
    return total, processes


runs = []
# Alternate the order to reduce thermal/order bias across fresh processes.
for trial in range(1, int(os.environ.get("BENCH_TRIALS", "3")) + 1):
    order = [('lua_ls', luals), ('emmylua_ls', emmy)]
    if trial % 2 == 0:
        order.reverse()
    for order_index, (server, command) in enumerate(order, 1):
        label = f'{server}-{trial}'
        run_state = state / label
        run_state.mkdir(exist_ok=False)
        env = os.environ.copy()
        for variable in ['VIMINIT', 'LUA_INIT', 'NVIM_LISTEN_ADDRESS']:
            env.pop(variable, None)
        env.update({
            'HOME': str(run_state), 'NVIM_APPNAME': 'nvim',
            'NVIM_CONFIG_DIR': str(workspace), 'BENCH_ROOT': str(workspace),
            'BENCH_SERVER': server, 'BENCH_CMD': command,
            'BENCH_OUT': str(output / (label + '.json')),
        })
        for variable, subdir in [('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state'),
                                 ('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config')]:
            env[variable] = str(run_state / subdir)
        peak, server_peak, per_pid_peak = 0, 0, {}
        start = time.monotonic()
        with (output / (label + '.log')).open('w') as log:
            proc = subprocess.Popen([
                nvim, '--headless', '-i', 'NONE', '--cmd',
                'lua vim.g.r10_started = vim.uv.hrtime()', '-c',
                'luafile ' + str(Path(__file__).with_name('lua-servers.lua')), '-c', 'qa!',
            ], cwd=workspace, env=env, stdout=log, stderr=subprocess.STDOUT)
            while proc.poll() is None:
                rss, processes = memory(proc.pid)
                peak = max(peak, rss)
                server_peak = max(server_peak, rss - processes.get(proc.pid, 0))
                for pid, value in processes.items():
                    per_pid_peak[pid] = max(per_pid_peak.get(pid, 0), value)
                if time.monotonic() - start > 300:
                    proc.kill()
                    raise RuntimeError(label + ' exceeded 300 seconds')
                time.sleep(0.01)
        path = output / (label + '.json')
        data = json.loads(path.read_text()) if path.exists() else {}
        required = ['attach_ms', 'first_diagnostics_ms', 'diagnostics_settled_ms']
        valid = (
            data.get('server') == server and data.get('probe_detected') is True
            and data.get('lazydev_attached') is True and not data.get('error')
            and all(isinstance(data.get(k), (int, float)) and math.isfinite(data[k]) and data[k] > 0 for k in required)
            and len(data.get('completion_ms', [])) == 10
            and all(math.isfinite(x) and x > 0 for x in data.get('completion_ms', []))
            and len(data.get('completion_items', [])) == 10
            and all(x > 0 for x in data.get('completion_items', []))
        )
        if not valid:
            raise RuntimeError(label + ' has incomplete/invalid results; inspect JSON and log')
        data.update(executables={"nvim": nvim, "server": command}, trial=trial, order_index=order_index, exit_code=proc.returncode, peak_tree_rss_kib=peak,
                    peak_server_rss_kib=server_peak)
        if data.get('completion_ms'):
            data['completion_median_ms'] = statistics.median(data['completion_ms'])
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
        runs.append(data)
        print(label, json.dumps({k: v for k, v in data.items() if k in [
            'attach_ms', 'first_diagnostics_ms', 'diagnostics_settled_ms',
            'completion_median_ms', 'peak_tree_rss_kib', 'peak_server_rss_kib',
            'exit_code', 'error', 'lazydev_attached']}), flush=True)
        if proc.returncode or data.get('error'):
            raise RuntimeError(label + ' failed; inspect log and raw JSON')
(output / 'summary.json').write_text(json.dumps(runs, indent=2, ensure_ascii=False) + '\n')
