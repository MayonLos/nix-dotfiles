#!/usr/bin/env python3
"""Private mock of the mayon-voice control socket for screenshots and demos.

Answers `status` with the current phase and flips idle/recording on `toggle`.
Never talks to the real daemon: it binds inside $XDG_RUNTIME_DIR/mayon-voice.
"""
import json
import os
import socket
import threading

directory = os.path.join(os.environ["XDG_RUNTIME_DIR"], "mayon-voice")
os.makedirs(directory, mode=0o700, exist_ok=True)
os.chmod(directory, 0o700)
path = os.path.join(directory, "control.sock")
try:
    os.unlink(path)
except FileNotFoundError:
    pass

state = {"phase": "idle", "engine": "sensevoice", "device": "cpu", "delivery": "fcitx", "error": None}
server = socket.socket(socket.AF_UNIX)
server.bind(path)
server.listen(8)


def handle(connection):
    try:
        line = connection.makefile().readline().strip()
        if line in ("toggle", "start", "stop"):
            if line == "stop" or (line == "toggle" and state["phase"] != "idle"):
                state["phase"] = "idle"
            else:
                state["phase"] = "recording"
        connection.sendall((json.dumps(state, ensure_ascii=False) + "\n").encode())
    finally:
        connection.close()


while True:
    client, _ = server.accept()
    threading.Thread(target=handle, args=(client,), daemon=True).start()
