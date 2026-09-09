"""Tests for ``neuro ci smoke-test`` against a stand-in launcher backend."""

from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
from typer.testing import CliRunner

from neurocli.cli import app

runner = CliRunner()


class _HealthyBackend(BaseHTTPRequestHandler):
    """Serves the realistic shapes each smoke-test step parses."""

    def log_message(self, *_args: object) -> None:
        return

    def _send(self, code: int, payload: object) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path == "/api/launcher/modules":
            self._send(200, [{"id": "neurocnl"}, {"id": "neurohub"}])
        elif self.path == "/api/suite/health":
            self._send(200, {"status": "ok", "version": "dev"})
        elif self.path == "/api/jupyter/health":
            self._send(200, {"status": "ok"})
        else:
            self._send(404, {"error": "not_found"})

    do_POST = do_PUT = do_DELETE = do_GET


class _FailingBackend(_HealthyBackend):
    """Healthy everywhere except Suite API health, which 500s."""

    def do_GET(self) -> None:
        if self.path == "/api/suite/health":
            self._send(500, {"detail": "boom"})
            return
        super().do_GET()


@pytest.fixture()
def fake_backend(monkeypatch):
    server = ThreadingHTTPServer(("127.0.0.1", 0), _HealthyBackend)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{server.server_address[1]}"
    monkeypatch.setenv("NMTK_LAUNCHER_URL", base)
    monkeypatch.setenv("NMTK_SUITE_API_URL", base)
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "test-token")
    yield base
    server.shutdown()
    server.server_close()


@pytest.fixture()
def failing_backend(monkeypatch):
    server = ThreadingHTTPServer(("127.0.0.1", 0), _FailingBackend)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{server.server_address[1]}"
    monkeypatch.setenv("NMTK_LAUNCHER_URL", base)
    monkeypatch.setenv("NMTK_SUITE_API_URL", base)
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "test-token")
    yield base
    server.shutdown()
    server.server_close()


def test_smoke_test_reports_every_step(fake_backend):
    result = runner.invoke(app, ["ci", "smoke-test", "--json"])
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    assert payload["status"] == "ok"
    by_name = {step["name"]: step for step in payload["steps"]}
    assert by_name["list_modules"]["module_count"] == 2
    assert by_name["suite_health"]["version"] == "dev"
    assert by_name["jupyter_health"]["ok"] is True


def test_smoke_test_names_the_failing_step(failing_backend):
    result = runner.invoke(app, ["ci", "smoke-test", "--json"])
    assert result.exit_code == 2
    payload = json.loads(result.stdout)
    assert payload["error"] == "smoke_test_failed"
    assert payload["step"] == "suite_health"
    assert payload["status_code"] == 500
