"""ServerForge demo app: a tiny notes board that Ansible deploys and Jenkins releases.

Standard library only, so a release is just files: no pip install on the server.

    python3 -m serverforge_app            # http://127.0.0.1:8000

Settings (environment variables, set by the systemd unit):
    SF_BIND      address to listen on            (default 127.0.0.1 - nginx is in front)
    SF_PORT      port                            (default 8000)
    SF_DATA_DIR  where notes.json lives          (default ./data)
    SF_ENV       staging / production / dev      (default dev)

Endpoints: /  /healthz  /api/info  /api/notes (GET, POST)  /metrics
"""

from __future__ import annotations

import html
import json
import os
import signal
import socket
import threading
import time
from collections import Counter
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs

PACKAGE_DIR = Path(__file__).resolve().parent
RELEASE_DIR = PACKAGE_DIR.parent
MAX_NOTES = 200
MAX_NOTE_LEN = 280
MAX_BODY = 4096


def read_version() -> str:
    """VERSION sits next to the package: app/VERSION in Git, <release>/VERSION on a server."""
    version_file = RELEASE_DIR / "VERSION"
    if version_file.is_file():
        return version_file.read_text(encoding="utf-8").strip()
    return "dev"


def release_is_broken() -> bool:
    """A release built with `build-app.sh --broken` carries a BROKEN marker.

    It starts normally but fails its health check, which is exactly what a bad
    release looks like in real life. deploy.yml must notice and roll back.
    """
    return (RELEASE_DIR / "BROKEN").exists()


class NoteStore:
    """Notes kept in one JSON file, written atomically (temp file + rename)."""

    def __init__(self, data_dir: Path) -> None:
        self.path = data_dir / "notes.json"
        self.lock = threading.Lock()
        data_dir.mkdir(parents=True, exist_ok=True)

    def all(self) -> list[dict]:
        with self.lock:
            return self._load()

    def add(self, text: str) -> dict:
        text = " ".join(text.split())  # collapse whitespace and newlines
        if not text:
            raise ValueError("note is empty")
        if len(text) > MAX_NOTE_LEN:
            raise ValueError(f"note is longer than {MAX_NOTE_LEN} characters")
        note = {"text": text, "at": int(time.time()), "host": socket.gethostname()}
        with self.lock:
            notes = self._load()
            notes.append(note)
            notes = notes[-MAX_NOTES:]
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps(notes), encoding="utf-8")
            os.replace(tmp, self.path)  # atomic on the same filesystem
        return note

    def _load(self) -> list[dict]:
        try:
            return json.loads(self.path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError):
            return []


class App:
    def __init__(self, data_dir: Path, env: str) -> None:
        self.version = read_version()
        self.env = env
        self.host = socket.gethostname()
        self.started = time.time()
        self.broken = release_is_broken()
        self.notes = NoteStore(data_dir)
        self.requests: Counter[tuple[str, int]] = Counter()
        self.lock = threading.Lock()

    def count(self, path: str, status: int) -> None:
        known = path if path in ("/", "/healthz", "/api/info", "/api/notes", "/metrics") else "other"
        with self.lock:
            self.requests[(known, status)] += 1

    def info(self) -> dict:
        return {
            "app": "serverforge",
            "version": self.version,
            "env": self.env,
            "host": self.host,
            "uptime_seconds": int(time.time() - self.started),
        }

    def metrics(self) -> str:
        lines = [
            "# HELP serverforge_build_info Version of the running release.",
            "# TYPE serverforge_build_info gauge",
            f'serverforge_build_info{{version="{self.version}",env="{self.env}"}} 1',
            "# HELP serverforge_http_requests_total HTTP requests by path and status.",
            "# TYPE serverforge_http_requests_total counter",
        ]
        with self.lock:
            for (path, status), n in sorted(self.requests.items()):
                lines.append(f'serverforge_http_requests_total{{path="{path}",status="{status}"}} {n}')
        lines += [
            "# HELP serverforge_notes Notes currently stored.",
            "# TYPE serverforge_notes gauge",
            f"serverforge_notes {len(self.notes.all())}",
        ]
        return "\n".join(lines) + "\n"

    def page(self) -> str:
        items = "".join(
            f"<li><span>{html.escape(n['text'])}</span><small>{html.escape(n.get('host', ''))}</small></li>"
            for n in reversed(self.notes.all()[-20:])
        ) or "<li class='empty'>No notes yet - add the first one.</li>"
        i = self.info()
        return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ServerForge - {html.escape(i['env'])}</title>
<style>
 :root {{ color-scheme: light dark; --a: #0f6b5c; }}
 body {{ font: 16px/1.5 system-ui, sans-serif; max-width: 640px; margin: 40px auto; padding: 0 16px; }}
 .badge {{ display: inline-block; padding: 2px 10px; border-radius: 99px; border: 1px solid var(--a); color: var(--a); font-size: .85rem; }}
 ul {{ padding: 0; list-style: none; }} li {{ display: flex; justify-content: space-between; gap: 12px; padding: 8px 0; border-bottom: 1px solid #8884; }}
 small {{ opacity: .6; }} input {{ width: 70%; padding: 8px; }} button {{ padding: 8px 14px; }}
</style></head><body>
<h1>ServerForge notes</h1>
<p><span class="badge">{html.escape(i['env'])}</span> version <b>{html.escape(i['version'])}</b> on <code>{html.escape(i['host'])}</code></p>
<form method="post" action="/api/notes"><input name="text" maxlength="{MAX_NOTE_LEN}" placeholder="Write a note" required> <button>Add</button></form>
<ul>{items}</ul>
<p><small>Deployed by Ansible, released by Jenkins. Demo data only.</small></p>
</body></html>"""


def make_handler(app: App) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "serverforge"
        sys_version = ""

        def log_message(self, fmt: str, *args: object) -> None:  # one JSON line per request (journald)
            print(json.dumps({"ts": int(time.time()), "client": self.client_address[0], "msg": fmt % args}), flush=True)

        def send(self, status: int, body: str | bytes, ctype: str = "application/json", extra: dict | None = None) -> None:
            data = body.encode("utf-8") if isinstance(body, str) else body
            self.send_response(status)
            self.send_header("Content-Type", f"{ctype}; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Cache-Control", "no-store")
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(data)
            app.count(self.path.split("?")[0], status)

        def do_HEAD(self) -> None:
            self.do_GET()

        def do_GET(self) -> None:
            path = self.path.split("?")[0]
            if path == "/healthz":
                if app.broken:
                    self.send(HTTPStatus.INTERNAL_SERVER_ERROR, json.dumps({"status": "broken", "version": app.version}))
                else:
                    self.send(HTTPStatus.OK, json.dumps({"status": "ok", "version": app.version}))
            elif path == "/api/info":
                self.send(HTTPStatus.OK, json.dumps(app.info()))
            elif path == "/api/notes":
                self.send(HTTPStatus.OK, json.dumps(app.notes.all()))
            elif path == "/metrics":
                self.send(HTTPStatus.OK, app.metrics(), "text/plain; version=0.0.4")
            elif path == "/":
                self.send(HTTPStatus.OK, app.page(), "text/html")
            else:
                self.send(HTTPStatus.NOT_FOUND, json.dumps({"error": "not found"}))

        def do_POST(self) -> None:
            if self.path.split("?")[0] != "/api/notes":
                self.send(HTTPStatus.NOT_FOUND, json.dumps({"error": "not found"}))
                return
            length = int(self.headers.get("Content-Length") or 0)
            if length <= 0 or length > MAX_BODY:
                self.send(HTTPStatus.BAD_REQUEST, json.dumps({"error": "empty or too large body"}))
                return
            raw = self.rfile.read(length).decode("utf-8", errors="replace")
            is_form = self.headers.get("Content-Type", "").startswith("application/x-www-form-urlencoded")
            try:
                text = parse_qs(raw).get("text", [""])[0] if is_form else str(json.loads(raw).get("text", ""))
                note = app.notes.add(text)
            except (ValueError, AttributeError) as exc:
                self.send(HTTPStatus.BAD_REQUEST, json.dumps({"error": str(exc)}))
                return
            if is_form:  # browser form: go back to the page
                self.send(HTTPStatus.SEE_OTHER, "", "text/plain", {"Location": "/"})
            else:
                self.send(HTTPStatus.CREATED, json.dumps(note))

    return Handler


def serve(bind: str, port: int, data_dir: Path, env: str) -> ThreadingHTTPServer:
    app = App(data_dir, env)
    server = ThreadingHTTPServer((bind, port), make_handler(app))
    server.daemon_threads = True
    return server


def main() -> None:
    bind = os.environ.get("SF_BIND", "127.0.0.1")
    port = int(os.environ.get("SF_PORT", "8000"))
    data_dir = Path(os.environ.get("SF_DATA_DIR", "data"))
    env = os.environ.get("SF_ENV", "dev")
    server = serve(bind, port, data_dir, env)

    def stop(*_: object) -> None:  # systemd sends SIGTERM on stop/restart
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    print(json.dumps({"msg": "listening", "bind": bind, "port": port, "version": read_version(), "env": env}), flush=True)
    server.serve_forever()
    server.server_close()


if __name__ == "__main__":
    main()
