"""An opt-in list of Skifrei servers, kept current by their heartbeats."""

from hmac import compare_digest
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import re
from threading import Lock
from time import monotonic
from urllib.parse import urlsplit


MAX_SERVERS = 32
EXPIRE_SECONDS = 100
HOST = re.compile(r"[A-Za-z0-9][A-Za-z0-9.\-]{0,126}[A-Za-z0-9]|[A-Za-z0-9]|[0-9a-fA-F:]{2,45}")


def server_entry(data):
    if not isinstance(data, dict):
        return None
    entry = {}
    for name, limit in (("name", 48), ("map", 48), ("mode", 4), ("host", 128), ("ws", 256)):
        value = data.get(name)
        if not isinstance(value, str) or not value.isprintable() and value:
            return None
        entry[name] = value.strip()
        if len(entry[name]) > limit:
            return None
    for name, low, high in (("v", 1, 65535), ("port", 1, 65535), ("slots", 2, 32), ("players", 0, 32)):
        value = data.get(name)
        if type(value) is not int or not low <= value <= high:
            return None
        entry[name] = value
    if (not entry["name"] or not entry["map"] or entry["mode"] not in ("ctf", "hold")
            or entry["players"] > entry["slots"] or not (entry["host"] or entry["ws"])):
        return None
    if entry["host"] and not HOST.fullmatch(entry["host"]):
        return None
    if entry["ws"]:
        try:
            uri = urlsplit(entry["ws"])
            if (uri.scheme not in ("ws", "wss") or not uri.hostname or not HOST.fullmatch(uri.hostname)
                    or uri.username is not None or uri.fragment or uri.port == 0):
                return None
        except ValueError:
            return None
    return entry


class Directory(ThreadingHTTPServer):
    def __init__(self, address, token):
        super().__init__(address, Handler)
        self.token = token
        self.entries = {}
        self.lock = Lock()

    def active(self, now):
        self.entries = {key: item for key, item in self.entries.items() if item[0] > now}


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def reply(self, code, data=None):
        body = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode() if data is not None else b""
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        if self.path != "/servers":
            self.reply(HTTPStatus.NOT_FOUND)
            return
        with self.server.lock:
            self.server.active(monotonic())
            entries = sorted((entry for _, entry in self.server.entries.values()),
                             key=lambda entry: (-entry["players"], entry["name"].casefold()))
        self.reply(HTTPStatus.OK, {"servers": entries})

    def do_POST(self):
        if self.path != "/servers":
            self.reply(HTTPStatus.NOT_FOUND)
            return
        authorization = self.headers.get("Authorization", "").encode()
        if not compare_digest(authorization, b"Bearer " + self.server.token):
            self.reply(HTTPStatus.UNAUTHORIZED)
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            if not 0 < length <= 2048:
                raise ValueError
            entry = server_entry(json.loads(self.rfile.read(length)))
        except (ValueError, OSError, RecursionError):
            entry = None
        if entry is None:
            self.reply(HTTPStatus.BAD_REQUEST)
            return
        key = (entry["host"].lower(), entry["port"]) if entry["host"] else entry["ws"]
        with self.server.lock:
            now = monotonic()
            self.server.active(now)
            full = key not in self.server.entries and len(self.server.entries) >= MAX_SERVERS
            if not full:
                self.server.entries[key] = (now + EXPIRE_SECONDS, entry)
        self.reply(HTTPStatus.SERVICE_UNAVAILABLE if full else HTTPStatus.NO_CONTENT)


if __name__ == "__main__":
    token = os.environ.get("SKIFREI_DIRECTORY_TOKEN", "").encode()
    if not token:
        raise SystemExit("Set SKIFREI_DIRECTORY_TOKEN.")
    address = (os.environ.get("SKIFREI_DIRECTORY_BIND", "127.0.0.1"),
               int(os.environ.get("SKIFREI_DIRECTORY_PORT", "27304")))
    with Directory(address, token) as directory:
        directory.serve_forever()
