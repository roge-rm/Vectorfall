"""Serve the dashboard and pass round changes to the game through its state volume."""

from base64 import b64encode
from hmac import compare_digest
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import mimetypes
import os
import shutil
import time
from pathlib import Path
from tempfile import NamedTemporaryFile
from urllib.parse import unquote, urlsplit

WEB = Path(__file__).resolve().parent
STATE = Path(os.environ.get("SKIFREI_STATUS_DIR", "/state"))
PLAY = Path(os.environ.get("SKIFREI_PLAY_DIR", "/play")).resolve()
PASSWORD = os.environ.get("SKIFREI_ADMIN_PASSWORD", "")
mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/octet-stream", ".pck")


def status():
    path = STATE / "status.json"
    try:
        if time.time() - path.stat().st_mtime > 8:
            return None
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    data["game_port"] = int(os.environ.get("SKIFREI_PUBLIC_GAME_PORT", data["game_port"]))
    data["ws_port"] = int(os.environ.get("SKIFREI_PUBLIC_WS_PORT", data["ws_port"]))
    data["ws_url"] = os.environ.get("SKIFREI_PUBLIC_WS", "")
    data["browser"] = (PLAY / "index.html").is_file()
    data["admin"] = bool(PASSWORD)
    return data


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def reply(self, code, content, mime, cache="no-store"):
        self.send_response(code)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", cache)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "same-origin")
        self.end_headers()
        self.wfile.write(content)

    def json_reply(self, code, body):
        self.reply(code, json.dumps(body).encode(), "application/json")

    def do_GET(self):
        path = unquote(urlsplit(self.path).path)
        if path == "/api/status":
            self.json_reply(HTTPStatus.OK, status())
            return
        if path.startswith("/play/"):
            file = (PLAY / (path[6:] or "index.html")).resolve()
            if not file.is_relative_to(PLAY) or file.suffix not in {".html", ".js", ".wasm", ".pck", ".png", ".svg"}:
                self.send_error(HTTPStatus.NOT_FOUND)
                return
        else:
            routes = {"/": "index.html", "/app.css": "app.css", "/app.js": "app.js",
                      "/cover.webp": "cover.webp", "/icon.png": "icon.png",
                      "/BigShouldersDisplay-Black.ttf": "BigShouldersDisplay-Black.ttf",
                      "/IBMPlexSerif-Medium.ttf": "IBMPlexSerif-Medium.ttf"}
            if path not in routes:
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            file = WEB / routes[path]
        try:
            with file.open("rb") as stream:
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", mimetypes.guess_type(file.name)[0] or "application/octet-stream")
                self.send_header("Content-Length", str(file.stat().st_size))
                self.send_header("X-Content-Type-Options", "nosniff")
                self.end_headers()
                shutil.copyfileobj(stream, self.wfile)
        except FileNotFoundError:
            self.send_error(HTTPStatus.NOT_FOUND)

    def do_POST(self):
        if self.path != "/api/round" or not PASSWORD:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        expectation = b"Basic " + b64encode(("admin:" + PASSWORD).encode())
        supplied = self.headers.get("Authorization", "").encode()
        if not compare_digest(supplied, expectation):
            self.json_reply(HTTPStatus.UNAUTHORIZED, {"error": "Incorrect password."})
            return
        if self.headers.get("X-Skifrei-Admin") != "1" or self.headers.get_content_type() != "application/json":
            self.send_error(HTTPStatus.FORBIDDEN)
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 1 <= size <= 512:
                raise ValueError
            body = json.loads(self.rfile.read(size))
        except (ValueError, OSError):
            self.send_error(HTTPStatus.BAD_REQUEST)
            return
        current = status()
        if current is None:
            self.json_reply(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "The server is offline."})
            return
        if not isinstance(body, dict) or body.get("map") not in current["maps"]:
            self.json_reply(HTTPStatus.BAD_REQUEST, {"error": "Choose an arena."})
            return
        with NamedTemporaryFile(mode="w", dir=STATE, delete=False) as temporary:
            json.dump({"map": body["map"]}, temporary)
        Path(temporary.name).replace(STATE / "round.json")
        self.json_reply(HTTPStatus.ACCEPTED, {"ok": True})


if __name__ == "__main__":
    bind = os.environ.get("SKIFREI_WEB_BIND", "127.0.0.1")
    port = int(os.environ.get("SKIFREI_WEB_PORT", "27303"))
    ThreadingHTTPServer((bind, port), Handler).serve_forever()
