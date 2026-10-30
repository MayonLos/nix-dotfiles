"""Process-level tests with private sockets, synthetic audio and fake external tools."""
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time

binary = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix='mayon-voice-test-') as temp:
    root = Path(temp)
    (root/'bin').mkdir()
    (root/'engine').mkdir()
    (root/'config/mayon-voice').mkdir(parents=True)
    (root/'config/mayon-voice/config.toml').write_text('idle_seconds=2\nmax_record_seconds=2\n')
    def executable(name, source):
        file=root/'bin'/name
        file.write_text(f'#!{sys.executable}\n'+source)
        file.chmod(0o700)
    executable('pw-record', '''import signal,sys,wave,time
f=wave.open(sys.argv[-1],'wb');f.setnchannels(1);f.setsampwidth(2);f.setframerate(16000)
def stop(*args):
 f.close();sys.exit(0)
signal.signal(signal.SIGINT,stop)
while True:
 f.writeframes(b'\\0'*320);time.sleep(.01)
''')
    executable('busctl','import sys\nfrom pathlib import Path\nprint(\'s "test-focus"\' if sys.argv[-1]=="FocusToken" else (\'s "focus_changed"\' if Path('+repr(str(root/'focus-changed'))+').exists() else \'s "committed"\'))\n')
    executable('wl-copy','import sys\nfrom pathlib import Path\nPath('+repr(str(root/'clipboard'))+').write_text(sys.stdin.read())\n')
    executable('notify-send','import time\nfrom pathlib import Path\nif Path('+repr(str(root/'slow-notify'))+').exists():time.sleep(10)\n')
    executable('python3','import os,sys\nos.execv('+repr(sys.executable)+', ['+repr(sys.executable)+']+sys.argv[1:])\n')
    (root/'engine/worker.py').write_text('import sys,json,time\nfor line in sys.stdin:\n time.sleep(.25);print(json.dumps({"text":"测试 Nix 输入。"}),flush=True)\n')
    private_env={'HOME':temp,'XDG_RUNTIME_DIR':temp,'XDG_CONFIG_HOME':str(root/'config'),'PATH':str(root/'bin'),'MAYON_VOICE_ENGINE_DIR':str(root/'engine')}
    proc=subprocess.Popen([binary,'daemon'],env=private_env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    endpoint=root/'mayon-voice/control.sock'
    def request(command):
        with socket.socket(socket.AF_UNIX) as conn:
            conn.settimeout(3);conn.connect(str(endpoint));conn.sendall((command+'\n').encode())
            return json.loads(conn.makefile().readline())
    try:
        for _ in range(100):
            if endpoint.exists():break
            time.sleep(.02)
        assert request('status')['phase']=='idle'
        assert 'error' in request('bogus')
        (root/'slow-notify').touch()
        before=time.monotonic()
        started=subprocess.run([binary,'start'],env=private_env,capture_output=True,text=True)
        assert time.monotonic()-before<1.5,'notification blocked control socket'
        (root/'slow-notify').unlink()
        assert started.returncode==0,started.stderr
        assert json.loads(started.stdout)['phase']=='recording'
        assert request('start')['phase']=='recording'
        time.sleep(.1)
        recordings=list(endpoint.parent.glob('capture-*.wav'))
        assert len(recordings)==1 and recordings[0].stat().st_mode & 0o777 == 0o600
        assert request('stop')['phase']=='transcribing'
        assert 'error' in request('start')
        busy=subprocess.run([binary,'start'],env=private_env,capture_output=True)
        assert busy.returncode==1
        for _ in range(100):
            state=request('status')
            if state['phase']=='idle':break
            time.sleep(.02)
        assert state['delivery']=='fcitx',state
        assert not list(endpoint.parent.glob('capture-*.wav'))
        (root/'focus-changed').touch()
        assert request('start')['phase']=='recording'
        time.sleep(.1)
        assert request('stop')['phase']=='transcribing'
        for _ in range(100):
            state=request('status')
            if state['phase']=='idle':break
            time.sleep(.02)
        assert state['delivery']=='clipboard-manual-paste',state
        assert (root/'clipboard').read_text()=='测试 Nix 输入。'
        # Polling status must not retain the model beyond the configured idle timeout.
        proc.wait(timeout=4)
        assert proc.returncode==0,proc.stderr.read().decode()
        assert not endpoint.exists()
    finally:
        if proc.poll() is None:proc.send_signal(signal.SIGTERM);proc.wait(timeout=4)
    # Real inherited fd 3 activation, without touching the user's systemd manager.
    activated=root/'activated.sock'
    listener=socket.socket(socket.AF_UNIX);listener.bind(str(activated));listener.listen()
    pid=os.fork()
    if pid==0:
        os.dup2(listener.fileno(),3,inheritable=True)
        private_env.update(LISTEN_PID=str(os.getpid()),LISTEN_FDS='1')
        os.execve(binary,[binary,'daemon'],private_env)
    listener.close()
    try:
        with socket.socket(socket.AF_UNIX) as conn:
            conn.settimeout(3);conn.connect(str(activated));conn.sendall(b'status\n')
            assert json.loads(conn.makefile().readline())['phase']=='idle'
    finally:
        os.kill(pid,signal.SIGTERM);os.waitpid(pid,0)
print('PASS: commands, idempotent start, busy guard, 0600 audio, cleanup, idle exit, focus-change clipboard fallback, fd3 activation')
