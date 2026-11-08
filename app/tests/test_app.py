"""Unit tests for the demo app. Run: cd app && python -m pytest -q"""

from __future__ import annotations

import json
import threading
import urllib.error
import urllib.request
from pathlib import Path

import pytest

from serverforge_app import app as appmod


@pytest.fixture()
def server(tmp_path: Path):
    srv = appmod.serve("127.0.0.1", 0, tmp_path, "test")
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    yield f"http://127.0.0.1:{srv.server_address[1]}"
    srv.shutdown()
    srv.server_close()


def get(url: str) -> tuple[int, str]:
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def post(url: str, body: bytes, ctype: str = "application/json") -> tuple[int, str]:
    req = urllib.request.Request(url, data=body, headers={"Content-Type": ctype}, method="POST")

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):  # keep the 303 visible to the test
            return None

    opener = urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(req, timeout=5) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def test_health_reports_version(server: str) -> None:
    status, body = get(server + "/healthz")
    assert status == 200
    data = json.loads(body)
    assert data["status"] == "ok"
    assert data["version"] == (Path(appmod.__file__).parent.parent / "VERSION").read_text().strip()


def test_notes_roundtrip_json_and_form(server: str) -> None:
    assert post(server + "/api/notes", json.dumps({"text": "  hello\n world "}).encode())[0] == 201
    assert post(server + "/api/notes", b"text=from+a+form", "application/x-www-form-urlencoded")[0] == 303
    status, body = get(server + "/api/notes")
    assert status == 200
    assert [n["text"] for n in json.loads(body)] == ["hello world", "from a form"]


def test_rejects_bad_notes(server: str) -> None:
    assert post(server + "/api/notes", json.dumps({"text": "   "}).encode())[0] == 400
    assert post(server + "/api/notes", json.dumps({"text": "x" * 281}).encode())[0] == 400
    assert post(server + "/api/notes", b"not json")[0] == 400
    assert post(server + "/api/notes", b"x" * 5000)[0] == 400


def test_page_escapes_html(server: str) -> None:
    post(server + "/api/notes", json.dumps({"text": "<script>alert(1)</script>"}).encode())
    status, body = get(server + "/")
    assert status == 200
    assert "<script>alert(1)</script>" not in body
    assert "&lt;script&gt;" in body


def test_metrics_and_404(server: str) -> None:
    get(server + "/healthz")
    assert get(server + "/nope")[0] == 404
    status, body = get(server + "/metrics")
    assert status == 200
    assert 'serverforge_http_requests_total{path="/healthz",status="200"} 1' in body
    assert 'serverforge_http_requests_total{path="other",status="404"} 1' in body
    assert "serverforge_build_info" in body


def test_notes_are_capped_and_persisted(tmp_path: Path) -> None:
    store = appmod.NoteStore(tmp_path)
    for i in range(appmod.MAX_NOTES + 5):
        store.add(f"note {i}")
    notes = appmod.NoteStore(tmp_path).all()  # a new store reads the same file
    assert len(notes) == appmod.MAX_NOTES
    assert notes[0]["text"] == "note 5"


def test_broken_release_fails_health(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(appmod, "release_is_broken", lambda: True)
    srv = appmod.serve("127.0.0.1", 0, tmp_path, "test")
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    try:
        status, body = get(f"http://127.0.0.1:{srv.server_address[1]}/healthz")
        assert status == 500
        assert json.loads(body)["status"] == "broken"
    finally:
        srv.shutdown()
        srv.server_close()
