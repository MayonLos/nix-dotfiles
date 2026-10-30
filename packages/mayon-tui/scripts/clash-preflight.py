"""Service preflight: diagnostics are fixed strings, never core output or config contents."""
import os
import http.client
import time
import tomllib
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def stop_tun(path, pid, data):
    # Locked 1.19.24 installs signal.Notify only after hub.Parse returns. A
    # SIGTERM while sing-tun.New is still adding rules otherwise skips Shutdown.
    # PATCH serializes on tunMux, waits for construction, then removes its rules
    # before systemd sends SIGTERM. Do not touch the saved user's TUN setting.
    class UnixHTTP(http.client.HTTPConnection):
        def connect(self):
            self.sock = socket.socket(socket.AF_UNIX)
            self.sock.settimeout(15)
            self.sock.connect(path)

    try:
        with open(Path(data) / "settings.toml", "rb") as settings:
            expected_tun = tomllib.load(settings).get("tun", True)
    except (OSError, tomllib.TOMLDecodeError):
        expected_tun = True
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if pid and not Path(f"/proc/{pid}").exists():
            return
        # The controller is created before initial updateTun. Do not PATCH too
        # early and allow that initial update to enable TUN again afterward.
        if expected_tun and not Path("/sys/class/net/mayon-clash").exists():
            time.sleep(0.05)
            continue
        connection = UnixHTTP("mihomo")
        try:
            connection.request("PATCH", "/configs", '{"tun":{"enable":false}}',
                               {"Content-Type": "application/json"})
            response = connection.getresponse()
            if 200 <= response.status < 300:
                return
        except (OSError, http.client.HTTPException):
            pass
        finally:
            connection.close()
        time.sleep(0.05)
    fail("停止前未能确认 TUN 清理；请检查 mayon-clash 单元状态。")


if len(sys.argv) > 1 and sys.argv[1] == "stop":
    stop_tun(sys.argv[2], sys.argv[4] if len(sys.argv) > 4 else None, sys.argv[3])
    sys.exit(0)


data, mihomo, geoip, geosite, mmdb = sys.argv[1:]
data = Path(data)
if not data.is_dir():
    fail("配置目录不存在；请先在 TUI 添加订阅。")
for source, name in [(geoip, "GeoIP.dat"), (geosite, "GeoSite.dat"), (mmdb, "Country.mmdb")]:
    target = data / name
    if not target.exists():
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=data, prefix=".geo-initial-", delete=False) as destination:
                temporary = Path(destination.name)
                with open(source, "rb") as origin:
                    shutil.copyfileobj(origin, destination)
                destination.flush()
                os.fsync(destination.fileno())
            temporary.replace(target)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
config = data / "config.yaml"
if not config.is_file():
    fail("runtime 配置不存在；请先在 TUI 选择订阅。")
try:
    result = subprocess.run([mihomo, "-t", "-d", str(data), "-f", str(config)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=45)
except (OSError, subprocess.TimeoutExpired):
    fail("mihomo 配置校验失败或超时；详细内容已隐藏。")
if result.returncode:
    fail("mihomo 配置校验失败；请在 TUI 更新或重新选择订阅。")
