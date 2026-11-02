#!/usr/bin/env python3
"""PTY simulator for the serial screenshots and manual visual checks.

It creates a private HOME/XDG tree, a `serial-mayon` config keyed to the simulated port and a
pseudo terminal that streams representative lines. Never touches a real serial device or the
user's data directories.

Used by the review screenshot harness kept outside the source tree; it can also run alone:
``python3 feed.py <directory>`` prints the port path and feeds until interrupted.
"""
import json
import math
import os
import pty
import select
import sys
import threading
import time
import tty

PORT_NAME = "mcu-uart"
FLASH_COMMAND = (
    "printf 'SIMULATED FLASH: UART released\\n'; sleep 1; "
    "printf 'verify OK - reconnect UART\\n'"
)


def write_config(home, port, flash_dir):
    """The same files and schema the Rust and C++ tools share, mode 0600."""
    config_dir = os.path.join(home, ".config", "serial-mayon")
    os.makedirs(config_dir, mode=0o700, exist_ok=True)
    profile = {
        "settings": {"baud": 115200, "bits": 8, "parity": "none", "stop": 1,
                     "flow": "none", "dtr": False, "rts": False},
        "encoding": "Utf8",
        "ending": "CRLF",
        "flash": FLASH_COMMAND,
        "flash_dir": str(flash_dir),
    }
    config = {
        "devices": {f"0000:0000:{port}:": profile},
        "favorites": [
            {"name": "读取状态", "value": "status", "hex": False},
            {"name": "STM32 bootloader sync", "value": "7F", "hex": True},
            {"name": "复位并打印版本", "value": "reset ; version", "hex": False},
        ],
        "highlights": ["ERROR", "WARN", "FAULT"],
        "scrollback": 100000,
    }
    path = os.path.join(config_dir, "config.json")
    with open(path, "w", encoding="utf-8") as file:
        json.dump(config, file, ensure_ascii=False)
    os.chmod(path, 0o600)


def message_for(index):
    if index % 11 == 0:
        return "\x1b[32mINFO\x1b[0m PTY 模拟 STM32 · tick={} · 系统运行中\r\n".format(index)
    if index % 29 == 0:
        return "\x1b[33mWARN\x1b[0m ADC 电压接近阈值 · 检查采样窗口\r\n"
    if index % 53 == 0:
        return "\x1b[31mERROR\x1b[0m simulated timeout · 已恢复\r\n"
    return "temp={:.2f},vbat={:.3f}\r\n".format(
        26 + 2 * math.sin(index / 12), 3.3 + 0.25 * math.cos(index / 9))


class Simulator:
    """Owns the PTY master and streams lines; replies ACK to anything written."""

    def __init__(self, directory, interval=0.08):
        self.directory = directory
        self.interval = interval
        self.master = None
        self.slave = None
        self.port = os.path.join(directory, PORT_NAME)
        self._stop = threading.Event()
        self._thread = None

    def start(self):
        self.master, self.slave = pty.openpty()
        tty.setraw(self.slave)
        tty.setraw(self.master)
        if os.path.lexists(self.port):
            os.unlink(self.port)
        os.symlink(os.ttyname(self.slave), self.port)
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        return self.port

    def _run(self):
        index = 0
        while not self._stop.wait(self.interval):
            try:
                os.write(self.master, message_for(index).encode())
                readable, _, _ = select.select([self.master], [], [], 0)
                if readable:
                    received = os.read(self.master, 4096)
                    if received:
                        os.write(self.master, b"ACK " + received.rstrip(b"\r\n") + b"\r\n")
                index += 1
            except OSError:
                time.sleep(0.2)

    def stop(self):
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=2)
        for fd in (self.master, self.slave):
            if fd is not None:
                try:
                    os.close(fd)
                except OSError:
                    pass
        self.master = self.slave = None


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    os.makedirs(root, mode=0o700, exist_ok=True)
    home = os.path.join(root, "home")
    os.makedirs(home, mode=0o700, exist_ok=True)
    simulator = Simulator(root)
    port = simulator.start()
    write_config(home, port, root)
    print(port, flush=True)
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        simulator.stop()


if __name__ == "__main__":
    main()
