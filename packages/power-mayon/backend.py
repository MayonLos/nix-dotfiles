"""Unprivileged power telemetry and policy. No sysfs writes or shell execution."""
import argparse
from contextlib import contextmanager
import csv
import fcntl
import json
import math
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import time

PROFILES = ('power-saver', 'balanced', 'performance')
SYS = Path(os.environ.get('POWER_MAYON_SYSFS', '/sys'))
PROC = Path(os.environ.get('POWER_MAYON_PROCFS', '/proc'))
LIMIT = 720
MAX_FILE = 512 * 1024
DEFAULTS = {'enabled': False, 'ac': 'balanced', 'battery': 'power-saver', 'gamemode': 'keep'}


def read(path):
    try:
        return path.read_text().strip()
    except (OSError, UnicodeError):
        return None


def number(path):
    try:
        value = float(read(path))
        return value if math.isfinite(value) else None
    except (TypeError, ValueError):
        return None


def scaled(path, scale):
    value = number(path)
    return None if value is None else value / scale


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=1.5, check=True)
    return result.stdout.strip()


def root(kind):
    base = Path(os.environ.get('XDG_' + kind + '_HOME', str(Path.home() / ('.config' if kind == 'CONFIG' else '.local/state'))))
    return base / 'power-mayon'


def secure_dir(path):
    # Reject all existing symlink ancestors, including a symlinked XDG root.
    for part in [*reversed(path.parents), path]:
        if part.is_symlink():
            raise ValueError('拒绝符号链接目录: ' + str(part))
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.stat().st_uid != os.getuid():
        raise ValueError('目录不属于当前用户')
    path.chmod(0o700)


def load(path, default):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except FileNotFoundError:
        return default
    with os.fdopen(fd) as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > MAX_FILE:
            raise ValueError('无效或过大的状态文件')
        return json.load(stream)


def save(path, data):
    secure_dir(path.parent)
    if path.is_symlink():
        raise ValueError('拒绝符号链接文件')
    encoded = (json.dumps(data, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n').encode()
    if len(encoded) > MAX_FILE:
        raise ValueError('状态超过容量限制')
    fd, temporary = tempfile.mkstemp(prefix='.power-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def acquire(lock):
    deadline = time.monotonic() + 10
    while True:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return
        except BlockingIOError:
            if time.monotonic() >= deadline:
                raise TimeoutError('另一个电源操作仍持有锁')
            time.sleep(0.05)


@contextmanager
def locked():
    directory = root('STATE')
    secure_dir(directory)
    fd = os.open(directory / 'lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as lock:
        if os.fstat(lock.fileno()).st_uid != os.getuid():
            raise ValueError('lock owner mismatch')
        acquire(lock)
        yield


def config():
    value = load(root('CONFIG') / 'config.json', DEFAULTS.copy())
    if isinstance(value, dict) and set(value) == {'enabled', 'ac', 'battery'}:
        value = {**value, 'gamemode': 'keep'}
    if (not isinstance(value, dict) or set(value) != set(DEFAULTS)
            or type(value['enabled']) is not bool
            or value['ac'] not in PROFILES or value['battery'] not in PROFILES
            or value['gamemode'] not in ('keep', *PROFILES)):
        raise ValueError('config.json 无效，需 enabled(bool)、ac、battery、gamemode')
    return value


def batteries():
    result = []
    for path in sorted((SYS / 'class/power_supply').glob('*')):
        if read(path / 'type') != 'Battery' or read(path / 'present') == '0':
            continue
        voltage = scaled(path / 'voltage_now', 1e6)
        def energy(field):
            value = scaled(path / ('energy_' + field), 1e6)
            if value is None and voltage:
                charge = scaled(path / ('charge_' + field), 1e6)
                value = None if charge is None else charge * voltage
            return value
        full, design, now = energy('full'), energy('full_design'), energy('now')
        watts = scaled(path / 'power_now', 1e6)
        if watts is None and voltage:
            current = scaled(path / 'current_now', 1e6)
            watts = None if current is None else abs(current * voltage)
        if watts is not None:
            watts = abs(watts)
        status = read(path / 'status')
        remaining = now if status == 'Discharging' else (max(0, full - now) if full is not None and now is not None and status == 'Charging' else None)
        seconds = int(remaining / watts * 3600) if remaining is not None and watts and watts > 0.1 else None
        result.append({'name': path.name, 'percent': number(path / 'capacity'), 'status': status,
                       'health_percent': full / design * 100 if full is not None and design else None,
                       'cycles': number(path / 'cycle_count'), 'power_w': watts,
                       'energy_wh': now, 'full_wh': full, 'design_wh': design,
                       'voltage_v': voltage, 'energy_source': 'energy_uw_h' if number(path / 'energy_full') is not None else 'estimated_charge_times_voltage', 'time_to_empty_s': seconds if status == 'Discharging' else None,
                       'time_to_full_s': seconds if status == 'Charging' else None})
    return result


def ac_online():
    values = [read(p / 'online') for p in (SYS / 'class/power_supply').glob('*')
              if read(p / 'type') not in ('Battery', None)]
    return True if '1' in values else (False if '0' in values else None)


def conservation():
    nodes = list((SYS / 'bus/platform/drivers/ideapad_acpi').glob('*/conservation_mode'))
    value = read(nodes[0]) if len(nodes) == 1 else None
    return {'available': value in ('0', '1'), 'enabled': value == '1' if value in ('0', '1') else None,
            'kind': 'firmware-conservation', 'threshold_percent': None}


def sensors():
    temps, fans = [], []
    for path in sorted((SYS / 'class/hwmon').glob('hwmon*')):
        chip = read(path / 'name') or path.name
        # Do not touch NVIDIA's device attributes while it may be asleep.
        if 'nvidia' in chip.lower():
            continue
        for attr in sorted(path.glob('temp*_input')):
            value = scaled(attr, 1000)
            if value is not None:
                temps.append({'name': chip + '/' + (read(attr.with_name(attr.name.replace('_input', '_label'))) or attr.stem), 'celsius': value})
        for attr in sorted(path.glob('fan*_input')):
            value = number(attr)
            if value is not None:
                fans.append({'name': chip + '/' + (read(attr.with_name(attr.name.replace('_input', '_label'))) or attr.stem), 'rpm': value})
    return temps, fans


def process_snapshot():
    result = {}
    for path in PROC.glob('[0-9]*'):
        text = read(path / 'stat')
        if not text or ')' not in text:
            continue
        try:
            name = text[text.index('(') + 1:text.rindex(')')]
            fields = text[text.rindex(')') + 2:].split()
            # comm may contain spaces and parentheses; key includes starttime.
            result[(int(path.name), int(fields[19]))] = (name, int(fields[11]) + int(fields[12]))
        except (ValueError, IndexError):
            continue
    return result


def cpu_snapshot():
    line = (read(PROC / 'stat') or '').splitlines()
    if not line or not line[0].startswith('cpu '):
        return None
    try:
        ticks = list(map(int, line[0].split()[1:9]))
        return sum(ticks), ticks[3] + ticks[4]
    except (ValueError, IndexError):
        return None


def rapl():
    # Top-level package zones only: never add their nested core/uncore zones.
    result = {}
    for path in (SYS / 'class/powercap').glob('intel-rapl:*'):
        if path.name.count(':') != 1 or not (read(path / 'name') or '').startswith('package-'):
            continue
        value, limit = number(path / 'energy_uj'), number(path / 'max_energy_range_uj')
        if value is not None and limit and limit > value >= 0:
            result[path.name] = (value, limit)
    return result


def delta_power(first, last, elapsed):
    if not first or set(first) != set(last) or elapsed <= 0:
        return None
    joules = 0
    for key, (value, limit) in last.items():
        old, old_limit = first[key]
        if limit != old_limit:
            return None
        joules += ((value - old) % limit) / 1e6
    return joules / elapsed


def gpu_data(nvidia=False):
    devices = []
    for path in sorted((SYS / 'bus/pci/devices').glob('*')):
        vendor, cls = read(path / 'vendor'), read(path / 'class') or ''
        if not cls.startswith('0x03'):
            continue
        if vendor not in ('0x10de', '0x8086'):
            continue
        devices.append({'pci': path.name, 'vendor': 'NVIDIA' if vendor == '0x10de' else 'Intel',
                        'runtime_status': read(path / 'power/runtime_status'), 'power_state': read(path / 'power_state'),
                        'power_w': None, 'temperature_c': None, 'utilization_percent': None})
    # Explicit opt-in, and only for a presently active GPU. A status race remains:
    # NVIDIA may suspend between the check and opening the driver. UI warns first.
    errors = []
    if nvidia:
        active = [d for d in devices if d['vendor'] == 'NVIDIA' and d['runtime_status'] == 'active' and d['power_state'] not in ('D3cold', 'D3hot')]
        for device in active:
            try:
                output = run('nvidia-smi', '-i', device['pci'], '--query-gpu=power.draw,temperature.gpu,utilization.gpu', '--format=csv,noheader,nounits')
                values = next(csv.reader([output]))
                for key, value in zip(('power_w', 'temperature_c', 'utilization_percent'), values):
                    try:
                        parsed = float(value.strip())
                        device[key] = parsed if math.isfinite(parsed) else None
                    except ValueError:
                        pass
            except (OSError, subprocess.SubprocessError, StopIteration) as error:
                errors.append('NVIDIA 查询不可用: ' + type(error).__name__)
    # fd scan includes graphics + compute, unlike --query-compute-apps alone.
    nodes = {'/dev/nvidia0', '/dev/nvidiactl', '/dev/nvidia-uvm', '/dev/nvidia-modeset'}
    for path in (SYS / 'class/drm').glob('*'):
        if read(path / 'device/vendor') == '0x10de':
            nodes.add('/dev/dri/' + path.name)
    clients = []
    for process in PROC.glob('[0-9]*'):
        used = set()
        for fd in (process / 'fd').glob('*'):
            try:
                target = os.readlink(fd)
                if target in nodes or target.startswith('/dev/nvidia-caps/'):
                    used.add(target)
            except OSError:
                continue
        if used:
            clients.append({'pid': int(process.name), 'name': read(process / 'comm') or '?', 'devices': sorted(used)})
    for device in devices:
        if device['vendor'] == 'Intel':
            for card in (SYS / 'class/drm').glob('card[0-9]*'):
                if (card / 'device').resolve() == (SYS / 'bus/pci/devices' / device['pci']).resolve():
                    device['frequency_mhz'] = number(card / 'gt_cur_freq_mhz')
                    device['utilization_percent'] = number(card / 'device/gpu_busy_percent')
    return {'devices': devices, 'processes': clients, 'query_enabled': nvidia,
            'process_scope': '仅当前用户可读 /proc/*/fd；设备打开者不代表已测得GPU负载', 'errors': errors}


def profile():
    try:
        current = run('powerprofilesctl', 'get')
        listing = run('powerprofilesctl', 'list')
        available = [p for p in PROFILES if any(line.strip().lstrip('* ').startswith(p + ':') for line in listing.splitlines())]
        return {'current': current if current in PROFILES else None, 'available': available, 'error': None}
    except (OSError, subprocess.SubprocessError):
        return {'current': None, 'available': [], 'error': 'PPD 不可用或无权限'}


def game_pending():
    runtime = os.environ.get('XDG_RUNTIME_DIR')
    return bool(runtime and (Path(runtime) / 'gaming-mode/state.json').exists())


def telemetry(nvidia=False, sample=False):
    cpu, processes, energy, started = cpu_snapshot() if sample else None, process_snapshot() if sample else {}, rapl() if sample else {}, time.monotonic()
    if sample:
        time.sleep(0.25)
    elapsed = time.monotonic() - started
    last = cpu_snapshot() if sample else None
    total = last[0] - cpu[0] if cpu and last else 0
    idle = last[1] - cpu[1] if cpu and last else 0
    power = delta_power(energy, rapl(), elapsed) if sample else None
    rows = []
    if sample and total > 0:
        for key, (name, ticks) in process_snapshot().items():
            if key not in processes:
                continue
            used = max(0, ticks - processes[key][1])
            if not used:
                continue
            share = min(1, used / total)
            rows.append({'pid': key[0], 'name': name, 'cpu_percent': share * 100,
                         'estimated_power_w': power * share if power is not None else None})
        rows.sort(key=lambda p: p['cpu_percent'], reverse=True)
    temps, fans = sensors()
    bats = batteries()
    return {'schema_version': 1, 'timestamp': int(time.time()), 'ac_online': ac_online(),
            'profile': profile(), 'batteries': bats, 'conservation': conservation(),
            'cpu': {'busy_percent': max(0, min(100, (total - idle) / total * 100)) if total > 0 else None,
                    'package_power_w': power, 'power_source': 'RAPL' if power is not None else 'unavailable',
                    'governor': read(SYS / 'devices/system/cpu/cpu0/cpufreq/scaling_governor'),
                    'frequency_mhz': scaled(SYS / 'devices/system/cpu/cpu0/cpufreq/scaling_cur_freq', 1000)},
            'gpu': gpu_data(nvidia), 'temperatures': temps, 'fans': fans,
            'processes': rows[:40], 'estimate_method': '估算：RAPL package W × 进程CPU ticks / 全CPU ticks（含idle）；不含GPU/IO，非单进程电表。无RAPL权限只显示CPU占比。',
            'automatic': {**config(), 'gamemode_pending': game_pending(), 'gamemode_policy': 'locked-active-override-or-keep'},
            'history': load(root('STATE') / 'history.json', [])[-LIMIT:]}


@contextmanager
def gaming_lock():
    runtime = os.environ.get('XDG_RUNTIME_DIR')
    if not runtime:
        raise ValueError('切换需要 XDG_RUNTIME_DIR（登录会话）')
    directory = Path(runtime) / 'gaming-mode'
    secure_dir(directory)
    fd = os.open(directory / 'lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as lock:
        acquire(lock)
        yield directory / 'state.json'


def apply_mode(mode):
    state = profile()
    if mode not in PROFILES or mode not in state['available']:
        raise ValueError('PPD 未提供此模式')
    if state['current'] != mode:
        run('powerprofilesctl', 'set', mode)
        if run('powerprofilesctl', 'get') != mode:
            raise RuntimeError('PPD 未确认目标模式')


def set_mode(mode):
    if mode not in PROFILES:
        raise ValueError('不支持的性能模式')
    with gaming_lock():
        if game_pending():
            raise ValueError('GameMode 活跃或恢复待处理，保留现有游戏策略')
        apply_mode(mode)


def tick():
    cfg = config()
    if not cfg['enabled']:
        return '自动规则关闭'
    # A single lock covers observing the journal and the enum change. Keep the
    # hook's saved original profile intact, and never interfere with recovery.
    with gaming_lock() as journal:
        if game_pending():
            try:
                state = load(journal, {})
            except (OSError, ValueError):
                return '让出 GameMode / 等待恢复'
            if (cfg['gamemode'] == 'keep' or not isinstance(state, dict)
                    or state.get('active') is not True or state.get('profile') not in PROFILES):
                return '让出 GameMode / 等待恢复'
            target = cfg['gamemode']
            apply_mode(target)
            return 'GameMode 规则: ' + target
        ac = ac_online()
        if ac is None:
            return '电源状态未知，保持模式'
        target = cfg['ac'] if ac else cfg['battery']
        apply_mode(target)
        return '自动规则: ' + target


def record(data):
    with locked():
        path = root('STATE') / 'history.json'
        values = load(path, [])
        if not isinstance(values, list):
            raise ValueError('history.json 无效')
        now = data['timestamp']
        if values and now - values[-1]['timestamp'] < 30:
            return
        battery_w = sum(b['power_w'] for b in data['batteries'] if b['power_w'] is not None)
        if not any(b['power_w'] is not None for b in data['batteries']):
            battery_w = None
        save(path, (values + [{'timestamp': now, 'battery_w': battery_w, 'cpu_w': data['cpu']['package_power_w'],
                               'ac_online': data['ac_online'], 'profile': data['profile']['current']}])[-LIMIT:])


def main():
    parser = argparse.ArgumentParser(description='power-mayon 电池与性能控制（默认TUI）')
    commands = parser.add_subparsers(dest='command', required=True)
    status = commands.add_parser('status')
    status.add_argument('--json', action='store_true')
    status.add_argument('--nvidia', action='store_true', help='显式查询active独显；有唤醒竞态')
    status.add_argument('--sample', action='store_true', help='采样250ms CPU/RAPL/进程')
    commands.add_parser('sample').add_argument('--nvidia', action='store_true')
    commands.add_parser('mode').add_argument('mode', choices=PROFILES)
    commands.add_parser('conservation').add_argument('value', choices=('on', 'off'))
    automatic = commands.add_parser('auto').add_subparsers(dest='action', required=True)
    for name in ('enable', 'disable', 'tick'):
        automatic.add_parser(name)
    configure = automatic.add_parser('configure')
    configure.add_argument('--ac', choices=PROFILES)
    configure.add_argument('--battery', choices=PROFILES)
    configure.add_argument('--gamemode', choices=('keep', *PROFILES))
    commands.add_parser('watch')
    args = parser.parse_args()
    if args.command in ('status', 'sample'):
        data = telemetry(args.nvidia, args.command == 'sample' or args.sample)
        if args.command == 'sample':
            record(data)
            data['history'] = load(root('STATE') / 'history.json', [])
        if args.command == 'sample' or args.json:
            print(json.dumps(data, ensure_ascii=False, allow_nan=False))
        else:
            print('模式: ' + str(data['profile']['current']) + '  电源: ' + str(data['ac_online']))
            for bat in data['batteries']:
                print(f"{bat['name']}: {bat['percent']}%  {bat['status']}  {bat['power_w']} W  健康 {bat['health_percent']}%  循环 {bat['cycles']}")
            print('自动规则: ' + ('开启' if data['automatic']['enabled'] else '关闭'))
    elif args.command == 'mode':
        with locked():
            if config()['enabled']:
                raise ValueError('先 auto disable 再手动选模式，以免被自动规则覆盖')
            set_mode(args.mode)
    elif args.command == 'conservation':
        with locked():
            if not conservation()['available']:
                raise ValueError('未找到唯一有效养护属性')
            run('legion-conservation', args.value)
            if conservation()['enabled'] != (args.value == 'on'):
                raise RuntimeError('养护状态未确认')
    elif args.command == 'auto':
        with locked():
            cfg = config()
            if args.action == 'tick':
                print(tick())
                return
            if args.action == 'configure':
                for key in ('ac', 'battery', 'gamemode'):
                    if getattr(args, key) is not None:
                        cfg[key] = getattr(args, key)
            else:
                cfg['enabled'] = args.action == 'enable'
            save(root('CONFIG') / 'config.json', cfg)
            print('已保存规则；30秒定时器或 auto tick 应用。' if cfg['enabled'] else '自动规则关闭；保留当前模式。')
    elif args.command == 'watch':
        while True:
            try:
                with locked():
                    tick()
                record(telemetry(sample=True))
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                print('power-mayon: ' + str(error), file=sys.stderr, flush=True)
            time.sleep(30)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, TypeError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print('power-mayon: ' + str(error), file=sys.stderr)
        sys.exit(1)
