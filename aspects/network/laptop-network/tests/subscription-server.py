"""Only synthetic loopback subscriptions and HTTP proxy traffic, inside the NixOS VM."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import time

CONFIG = b'''proxies:
  - {name: Local, type: http, server: 127.0.0.1, port: 18080}
proxy-groups:
  - {name: Select, type: select, proxies: [Local, DIRECT]}
rules:
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - MATCH,Select
'''


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_CONNECT(self):
        # Mihomo's HTTP outbound uses CONNECT even for a plain HTTP flow from TUN.
        if self.path != "198.19.0.2:18081":
            self.send_error(403)
            return
        self.send_response(200, "Connection Established")
        self.end_headers()
        request = self.rfile.readline(65536)
        while self.rfile.readline(65536).strip():
            pass
        hold = b"/hold" in request
        body = b"synthetic TUN proxy response\n"
        length = 1000000 if hold else len(body)
        self.wfile.write(f"HTTP/1.1 200 OK\r\nContent-Length: {length}\r\nConnection: close\r\n\r\n".encode() + body)
        self.wfile.flush()
        self.close_connection = True
        if hold:
            try:
                for _ in range(120):
                    self.wfile.write(b"x" * 100)
                    self.wfile.flush()
                    time.sleep(1)
            except (BrokenPipeError, ConnectionResetError):
                pass

    def do_GET(self):
        body = CONFIG if self.path == "/sub" else b"synthetic TUN proxy response\n"
        self.send_response(200)
        self.send_header("Content-Length", str(1000000 if "/hold" in self.path else len(body)))
        self.send_header("Subscription-Userinfo", "upload=12; download=34; total=100000; expire=2000000000")
        self.send_header("Profile-Title", "VM trial")
        self.send_header("Profile-Update-Interval", "12")
        self.end_headers()
        self.wfile.write(body)
        self.wfile.flush()
        if "/hold" in self.path:
            try:
                for _ in range(120):
                    self.wfile.write(b"x" * 100)
                    self.wfile.flush()
                    time.sleep(1)
            except (BrokenPipeError, ConnectionResetError):
                pass


ThreadingHTTPServer(("127.0.0.1", 18080), Handler).serve_forever()
