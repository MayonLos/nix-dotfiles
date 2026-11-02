#!/usr/bin/env python3
"""Minimal Mihomo controller over a Unix socket, plus a TCP subscription origin.

Used by clash/tests and the screenshot wrapper. No third-party modules: HTTP/1.1,
chunked streaming and the WebSocket handshake are implemented directly on sockets.
"""
import argparse
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import threading
import time

FIXTURE = {}
ACTIONS = None
REJECT_RELOAD = False
WRONG_CONFIGS = False
RELOAD_FAIL_ONCE = False
SETTINGS_CONFIGS = False
PUT_COUNT = 0
GET_COUNT = 0


def record(entry):
    if not ACTIONS:
        return
    with open(ACTIONS, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")


def strip_query(path):
    return path.split("?", 1)[0]


def read_request(conn):
    buffer = b""
    while b"\r\n\r\n" not in buffer:
        part = conn.recv(65536)
        if not part:
            return None
        buffer += part
        if len(buffer) > 1024 * 1024:
            return None
    head, _, rest = buffer.partition(b"\r\n\r\n")
    lines = head.decode("latin-1").split("\r\n")
    method, target, _ = lines[0].split(" ", 2)
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            key, value = line.split(":", 1)
            headers[key.strip().lower()] = value.strip()
    length = int(headers.get("content-length", "0") or 0)
    body = rest
    while len(body) < length:
        part = conn.recv(65536)
        if not part:
            break
        body += part
    return method, target, headers, body[:length]


def respond(conn, status, body=b"", headers=None, reason="OK"):
    headers = headers or {}
    if isinstance(body, str):
        body = body.encode()
    lines = ["HTTP/1.1 %d %s" % (status, reason), "Content-Length: %d" % len(body), "Connection: close", "Content-Type: application/json"]
    for key, value in headers.items():
        lines.append("%s: %s" % (key, value))
    conn.sendall(("\r\n".join(lines) + "\r\n\r\n").encode() + body)


def empty(conn):
    conn.sendall(b"HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")


def chunked(conn, lines, interval):
    conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n")
    index = 0
    try:
        while True:
            payload = (json.dumps(lines(index), ensure_ascii=False) + "\n").encode()
            conn.sendall(("%x\r\n" % len(payload)).encode() + payload + b"\r\n")
            index += 1
            time.sleep(interval)
    except OSError:
        return


def traffic_frame(index):
    return {"up": 100 + index * 10, "down": 200 + index * 20, "upTotal": 1000 + index * 10, "downTotal": 2000 + index * 20}


def log_frame(index):
    if index % 2 == 0:
        return {"type": "info", "payload": "load https://example.invalid/?token=fixture failed"}
    return {"type": "warning", "payload": "rule provider refreshed %d" % index}


def websocket(conn, headers):
    key = headers.get("sec-websocket-key", "")
    accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
    conn.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % accept).encode())
    payload = json.dumps(FIXTURE.get("connections", {}), ensure_ascii=False).encode()
    try:
        while True:
            length = len(payload)
            frame = bytearray([0x81])
            if length < 126:
                frame.append(length)
            elif length < 65536:
                frame.append(126)
                frame += struct.pack(">H", length)
            else:
                frame.append(127)
                frame += struct.pack(">Q", length)
            frame += payload
            conn.sendall(frame)
            time.sleep(1)
    except OSError:
        return


def group_delay(group):
    proxies = FIXTURE.get("proxies", {})
    nodes = proxies.get(group, {}).get("all", [])
    return {name: 42 for name in nodes}


def dispatch(conn, method, target, headers, body):
    path = strip_query(target)
    parts = [part for part in path.split("/") if part]
    if method == "GET" and path == "/version":
        respond(conn, 200, json.dumps({"version": "1.19.24", "meta": True}))
    elif method == "GET" and path == "/proxies":
        respond(conn, 200, json.dumps({"proxies": FIXTURE.get("proxies", {})}, ensure_ascii=False))
    elif method == "GET" and path == "/configs":
        global GET_COUNT
        GET_COUNT += 1
        config = FIXTURE.get("configs", {})
        if SETTINGS_CONFIGS:
            config = {"mode": "rule", "tun": {"enable": True}, "mixed-port": 7897}
        elif WRONG_CONFIGS and GET_COUNT == 1:
            config = {"mode": "rule", "tun": {"enable": False}, "mixed-port": 0}
        respond(conn, 200, json.dumps(config))
    elif method == "PUT" and path == "/configs":
        global PUT_COUNT
        PUT_COUNT += 1
        record({"method": method, "path": target, "body": body.decode("utf-8", "replace")})
        if REJECT_RELOAD or (RELOAD_FAIL_ONCE and PUT_COUNT == 1):
            respond(conn, 500, b"{}", reason="Rejected")
        else:
            empty(conn)
    elif method == "PUT" and len(parts) == 2 and parts[0] == "proxies":
        record({"method": method, "path": target, "body": body.decode("utf-8", "replace")})
        empty(conn)
    elif method == "GET" and len(parts) == 3 and parts[0] == "proxies" and parts[2] == "delay":
        record({"method": method, "path": target})
        respond(conn, 200, json.dumps({"delay": 42}))
    elif method == "GET" and len(parts) == 3 and parts[0] == "group" and parts[2] == "delay":
        record({"method": method, "path": target})
        respond(conn, 200, json.dumps(group_delay(parts[1]), ensure_ascii=False))
    elif method == "GET" and path == "/connections":
        if headers.get("upgrade", "").lower() == "websocket":
            record({"method": method, "path": target, "websocket": True})
            websocket(conn, headers)
        else:
            respond(conn, 200, json.dumps(FIXTURE.get("connections", {}), ensure_ascii=False))
    elif method == "DELETE" and path.startswith("/connections"):
        record({"method": method, "path": target})
        empty(conn)
    elif method == "GET" and path == "/providers/proxies":
        respond(conn, 200, json.dumps({"providers": {"Source": {"vehicleType": "HTTP", "type": "file", "proxies": [], "updatedAt": "2026-10-30T00:00:00Z", "ruleCount": 0}}}))
    elif method == "GET" and path == "/providers/rules":
        respond(conn, 200, json.dumps({"providers": {"Rules": {"vehicleType": "HTTP", "type": "file", "ruleCount": 10, "updatedAt": "2026-10-30T00:00:00Z"}}}))
    elif method == "GET" and path == "/rules":
        respond(conn, 200, json.dumps({"rules": [
            {"type": "DomainSuffix", "payload": "example.invalid", "proxy": "手动选择", "extra": {"hitCount": 3, "hitAt": "2026-10-30T00:00:00Z"}},
            {"type": "MATCH", "payload": "", "proxy": "GLOBAL"},
        ]}, ensure_ascii=False))
    elif method == "PUT" and len(parts) == 3 and parts[0] == "providers":
        record({"method": method, "path": target})
        empty(conn)
    elif method == "GET" and len(parts) == 4 and parts[0] == "providers" and parts[3] == "healthcheck":
        record({"method": method, "path": target})
        empty(conn)
    elif method == "POST" and path.startswith("/cache/"):
        record({"method": method, "path": target})
        empty(conn)
    elif method == "POST" and path == "/configs/geo":
        record({"method": method, "path": target})
        empty(conn)
    elif method == "GET" and path == "/traffic":
        record({"method": method, "path": target, "stream": "traffic"})
        chunked(conn, traffic_frame, 0.2)
    elif method == "GET" and path == "/logs":
        record({"method": method, "path": target, "stream": "logs"})
        chunked(conn, log_frame, 0.2)
    else:
        record({"method": method, "path": target, "unknown": True})
        respond(conn, 404, b"{}", reason="Not Found")


def handle(conn):
    try:
        request = read_request(conn)
        if request:
            dispatch(conn, *request)
    except OSError:
        pass
    finally:
        try:
            conn.close()
        except OSError:
            pass


def unix_server(path):
    if os.path.exists(path):
        os.unlink(path)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(64)
    while True:
        conn, _ = server.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()


def subscription_server(port, fixture_path):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(8)
    with open(fixture_path, "rb") as handle_file:
        body = handle_file.read()

    def serve(conn):
        try:
            request = read_request(conn)
            if not request:
                return
            method, target, _headers, _body = request
            path = strip_query(target)
            if path == "/sub":
                headers = {
                    "Profile-Title": "base64:RGVtbyB0aXRsZQ==",
                    "Profile-Update-Interval": "12",
                    "Subscription-Userinfo": "upload=1; download=2; total=10; expire=2000000000",
                }
                if method == "HEAD":
                    respond(conn, 200, b"", headers)
                else:
                    respond(conn, 200, body, headers)
            elif path == "/redirect":
                conn.sendall(b"HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:%d/sub\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" % port)
            elif path == "/slow":
                chunked(conn, lambda index: {"type": "info", "payload": "slow"}, 1)
            else:
                respond(conn, 404, b"", reason="Not Found")
        except OSError:
            pass
        finally:
            conn.close()

    def accept_loop():
        while True:
            conn, _ = server.accept()
            threading.Thread(target=serve, args=(conn,), daemon=True).start()

    threading.Thread(target=accept_loop, daemon=True).start()
    return server


def main():
    global FIXTURE, ACTIONS, REJECT_RELOAD, WRONG_CONFIGS, RELOAD_FAIL_ONCE, SETTINGS_CONFIGS
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", required=True)
    parser.add_argument("--fixture", required=True)
    parser.add_argument("--actions", default="")
    parser.add_argument("--http-port", type=int, default=-1)
    parser.add_argument("--subscription", default="")
    parser.add_argument("--port-file", default="")
    parser.add_argument("--reject-reload", action="store_true")
    parser.add_argument("--wrong-configs", action="store_true")
    parser.add_argument("--reload-fail-once", action="store_true")
    parser.add_argument("--settings-configs", action="store_true")
    args = parser.parse_args()
    with open(args.fixture, encoding="utf-8") as handle:
        FIXTURE = json.load(handle)
    ACTIONS = args.actions
    REJECT_RELOAD = args.reject_reload
    WRONG_CONFIGS = args.wrong_configs
    RELOAD_FAIL_ONCE = args.reload_fail_once
    SETTINGS_CONFIGS = args.settings_configs
    port = args.http_port
    if port >= 0 and args.subscription:
        server = subscription_server(port, args.subscription)
        port = server.getsockname()[1]
    if args.port_file:
        with open(args.port_file, "w", encoding="utf-8") as handle:
            handle.write("READY %s\nPORT %d\n" % (args.socket, port))
    threading.Thread(target=unix_server, args=(args.socket,), daemon=True).start()
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
