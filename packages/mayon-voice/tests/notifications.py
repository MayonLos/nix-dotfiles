"""Voice notification replacement and debounce against a private D-Bus server."""
import asyncio
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time


def serve(state_path):
    from dbus_next.aio import MessageBus
    from dbus_next.service import ServiceInterface, method, signal as dbus_signal

    class Notifications(ServiceInterface):
        def __init__(self):
            super().__init__('org.freedesktop.Notifications')
            self.next_id = 1
            self.active = {}
            self.events = []
            self.timers = {}

        def save(self):
            Path(state_path).write_text(json.dumps({'active': self.active, 'events': self.events}))

        def close(self, notification_id, reason):
            if notification_id in self.active:
                self.active.pop(notification_id)
                self.events.append({'kind': 'close', 'id': notification_id, 'reason': reason})
                timer = self.timers.pop(notification_id, None)
                if timer:
                    timer.cancel()
                self.save()
                self.NotificationClosed(notification_id, reason)

        @method()
        def Notify(self, app_name: 's', replaces_id: 'u', app_icon: 's', summary: 's', body: 's',
                   actions: 'as', hints: 'a{sv}', expire_timeout: 'i') -> 'u':
            notification_id = replaces_id if replaces_id in self.active else self.next_id
            if notification_id == self.next_id:
                self.next_id += 1
            timer = self.timers.pop(notification_id, None)
            if timer:
                timer.cancel()
            self.active[notification_id] = {'body': body, 'timeout': expire_timeout}
            self.events.append({'kind': 'notify', 'id': notification_id, 'replaces': replaces_id,
                                'body': body, 'timeout': expire_timeout,
                                'transient': hints.get('transient').value if 'transient' in hints else False,
                                'count': len(self.active)})
            if expire_timeout > 0:
                self.timers[notification_id] = asyncio.get_running_loop().call_later(
                    expire_timeout / 1000, self.close, notification_id, 1)
            self.save()
            return notification_id

        @method()
        def CloseNotification(self, notification_id: 'u'):
            self.close(notification_id, 3)

        @method()
        def GetCapabilities(self) -> 'as':
            return ['body', 'persistence']

        @method()
        def GetServerInformation(self) -> 'ssss':
            return ['private voice fixture', 'tests', '1', '1.2']

        @dbus_signal()
        def NotificationClosed(self, notification_id: 'u', reason: 'u') -> 'uu':
            return [notification_id, reason]

    class Fcitx(ServiceInterface):
        def __init__(self):
            super().__init__('org.mayon.Voice1')

        @method()
        def FocusToken(self) -> 's':
            return 'fixture-focus'

        @method()
        def CommitStringForFocus(self, token: 's', text: 's') -> 's':
            return 'committed'

    async def run():
        bus = await MessageBus().connect()
        notifications = Notifications()
        bus.export('/org/freedesktop/Notifications', notifications)
        bus.export('/mayon/voice', Fcitx())
        await bus.request_name('org.freedesktop.Notifications')
        await bus.request_name('org.fcitx.Fcitx5')
        notifications.save()
        await asyncio.Future()

    asyncio.run(run())


def run(binary):
    with tempfile.TemporaryDirectory(prefix='mayon-voice-notifications-') as temporary:
        root = Path(temporary)
        (root / 'bin').mkdir()
        (root / 'engine').mkdir()
        config = root / 'config/mayon-voice'
        config.mkdir(parents=True)
        (config / 'config.toml').write_text('idle_seconds=60\nmax_record_seconds=60\n')

        def executable(name, text):
            path = root / 'bin' / name
            path.write_text(f'#!{sys.executable}\n' + text)
            path.chmod(0o700)

        executable('pw-record', '''import signal,sys,time,wave
output=wave.open(sys.argv[-1],'wb');output.setnchannels(1);output.setsampwidth(2);output.setframerate(16000)
def stop(*args):output.close();sys.exit(0)
signal.signal(signal.SIGINT,stop)
while True:output.writeframes(b'\\0'*320);time.sleep(.01)
''')
        executable('python3', f'import os,sys\nos.execv({sys.executable!r},[{sys.executable!r}]+sys.argv[1:])\n')
        (root / 'engine/worker.py').write_text(
            'import sys,json,time\nfor line in sys.stdin:\n time.sleep(3);print(json.dumps({"text":"private fixture transcript"}),flush=True)\n')
        env = {'HOME': temporary, 'XDG_RUNTIME_DIR': temporary,
               'XDG_CONFIG_HOME': str(root / 'config'),
               'PATH': str(root / 'bin') + ':' + os.environ['PATH'],
               'DBUS_SESSION_BUS_ADDRESS': os.environ['DBUS_SESSION_BUS_ADDRESS'],
               'MAYON_VOICE_ENGINE_DIR': str(root / 'engine'), 'PYTHONPATH': os.pathsep.join(sys.path)}
        service = subprocess.Popen([sys.executable, __file__, '--serve', str(root / 'notices.json')],
                                   env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        process = None
        endpoint = root / 'mayon-voice/control.sock'

        def state():
            try:
                return json.loads((root / 'notices.json').read_text())
            except (FileNotFoundError, json.JSONDecodeError):
                return {'active': {}, 'events': []}

        def wait(predicate, timeout=3):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if service.poll() is not None:
                    raise AssertionError(service.stderr.read().decode())
                if predicate():
                    return
                time.sleep(.02)
            raise AssertionError(state())

        def request(command):
            with socket.socket(socket.AF_UNIX) as connection:
                connection.settimeout(3)
                connection.connect(str(endpoint))
                connection.sendall((command + '\n').encode())
                return json.loads(connection.makefile().readline())

        def start_daemon():
            child = subprocess.Popen([binary, 'daemon'], env=env, start_new_session=True,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            wait(lambda: endpoint.exists())
            assert request('status')['phase'] == 'idle'
            return child

        try:
            wait(lambda: (root / 'notices.json').exists())
            process = start_daemon()
            assert request('toggle')['phase'] == 'recording'
            wait(lambda: any('录音中' in item['body'] for item in state()['active'].values()))
            first_id = next(iter(state()['active']))
            repeat_start = time.monotonic()
            for index in range(20):
                time.sleep(max(0, repeat_start + (index + 1) / 30 - time.monotonic()))
                assert request('toggle')['phase'] == 'recording'
            time.sleep(.55)
            assert request('toggle')['phase'] == 'transcribing'
            for _ in range(3):
                time.sleep(.55)
                assert 'error' in request('toggle')
            wait(lambda: request('status')['phase'] == 'idle', timeout=4)
            wait(lambda: any(item['body'] == '语音输入完成' for item in state()['active'].values()))
            events = [item for item in state()['events'] if item['kind'] == 'notify']
            assert all(str(item['id']) == first_id and item['count'] == 1 for item in events), events
            assert all(item['transient'] for item in events)
            assert sum(item['body'] == '正在识别 · 请稍候' for item in events) == 1, events
            assert events[-1]['timeout'] == 4000
            assert all('private fixture transcript' not in item['body'] for item in events)
            wait(lambda: not state()['active'], timeout=5)
            assert request('start')['phase'] == 'recording'
            wait(lambda: bool(state()['active']))
            old_id = next(iter(state()['active']))
            stored = root / 'mayon-voice/notification.json'
            wait(stored.exists)
            assert stored.stat().st_mode & 0o777 == 0o600
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=3)
            process = None
            endpoint.unlink()
            assert old_id in state()['active']
            process = start_daemon()
            wait(lambda: old_id not in state()['active'])
            assert any(item['kind'] == 'close' and str(item['id']) == old_id for item in state()['events'])
            assert request('start')['phase'] == 'recording'
            wait(lambda: bool(state()['active']))
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=4)
            assert process.returncode == 0, process.stderr.read().decode()
            process = None
            wait(lambda: not state()['active'])
        finally:
            if process is not None and process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=4)
            service.terminate()
            service.wait(timeout=3)
    print('PASS: private D-Bus replacement, one busy notice, sliding toggle debounce, short completion, crash restart cleanup')


if __name__ == '__main__':
    if sys.argv[1] == '--serve':
        serve(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[2] == '--private':
        run(str(Path(sys.argv[1]).resolve()))
    else:
        env = {'PATH': os.environ['PATH'], 'HOME': tempfile.gettempdir(), 'PYTHONPATH': os.pathsep.join(sys.path)}
        dbus_cmd = ['dbus-run-session']
        # The nix build sandbox has no /etc/dbus-1/session.conf, so pin the
        # config shipped with pkgs.dbus when the caller supplies one.
        if os.environ.get('MAYON_VOICE_DBUS_SESSION_CONF'):
            dbus_cmd += ['--config-file', os.environ['MAYON_VOICE_DBUS_SESSION_CONF']]
        dbus_cmd += ['--', sys.executable, __file__, sys.argv[1], '--private']
        result = subprocess.run(dbus_cmd, env=env)
        sys.exit(result.returncode)
