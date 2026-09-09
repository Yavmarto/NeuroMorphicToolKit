"""Tests for ``neuro ci smoke-test`` against a stand-in launcher backend."""

from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

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


# ── neuro ci golden-paths ─────────────────────────────────────────────────────


class _GoldenBackend(_HealthyBackend):
    """Serve generate-v2 for any framework and (for snntorch_sim) a run job."""

    def do_GET(self) -> None:
        if self.path.startswith("/api/neurocnl/training/jobs/") and self.path.endswith("/events"):
            body = b'data: {"type": "done"}\n\n'
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def do_POST(self) -> None:
        if self.path == "/api/neurocnl/notebook/generate-v2":
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            framework = body.get("pipeline_config", {}).get("framework", "snntorch_sim")
            self._send(
                200,
                {
                    "workspace_folder": f"golden-{framework}",
                    "notebooks": [{"filename": f"pipeline_{framework}.ipynb", "target": framework}],
                    "trainable": framework == "snntorch_sim",
                },
            )
        elif self.path == "/api/neurocnl/notebook/run":
            self._send(202, {"job_id": "golden-job-1"})
        else:
            self._send(404, {"error": "not_found"})

    do_PUT = do_DELETE = do_POST


class _GoldenBackendFailsGenerate(_GoldenBackend):
    def do_POST(self) -> None:
        if self.path == "/api/neurocnl/notebook/generate-v2":
            self._send(422, {"detail": {"code": "compile_error", "message": "unknown node type"}})
            return
        super().do_POST()


def _golden_runner(base: str, monkeypatch, backend_cls=_GoldenBackend) -> CliRunner:
    server = ThreadingHTTPServer(("127.0.0.1", 0), backend_cls)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{server.server_address[1]}"
    monkeypatch.setenv("NMTK_SUITE_API_URL", base)
    yield base
    server.shutdown()
    server.server_close()


@pytest.fixture()
def golden_backend(monkeypatch):
    yield from _golden_runner(None, monkeypatch)


@pytest.fixture()
def golden_failing_backend(monkeypatch):
    yield from _golden_runner(None, monkeypatch, _GoldenBackendFailsGenerate)


def test_golden_paths_reports_every_combo(golden_backend, tmp_path: Path) -> None:
    out = tmp_path / "summary.json"
    result = runner.invoke(
        app,
        ["ci", "golden-paths", "--output", str(out), "--json"],
    )
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    assert payload["status"] == "ok"
    assert payload["failed"] == []
    by_id = {g["id"]: g for g in payload["golden_paths"]}
    assert len(by_id) == 5
    snntorch = by_id["nir+snntorch"]
    assert snntorch["generate"]["ok"] is True
    assert snntorch["run"]["ok"] is True
    assert snntorch["ok"] is True
    lava = by_id["nir+lava_sim"]
    assert lava["generate"]["ok"] is True
    assert lava["run"]["reason"] == "no_studio_training_adapter"
    assert lava["ok"] is True
    assert out.read_text().startswith("{")


def test_golden_paths_exits_nonzero_when_generate_fails(golden_failing_backend) -> None:
    result = runner.invoke(app, ["ci", "golden-paths", "--json"])
    assert result.exit_code == 1
    payload = json.loads(result.stdout)
    assert payload["status"] == "failed"
    assert "nir+snntorch" in payload["failed"]
    assert len(payload["failed"]) == 5


def test_golden_paths_missing_workspace_file(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("NMTK_SUITE_API_URL", "http://x.test")
    import neurocli.ci as ci_mod

    monkeypatch.setattr(ci_mod, "_golden_paths_dir", lambda: tmp_path)
    result = runner.invoke(app, ["ci", "golden-paths", "--json"])
    assert result.exit_code == 1
    payload = json.loads(result.stdout)
    assert payload["status"] == "failed"
