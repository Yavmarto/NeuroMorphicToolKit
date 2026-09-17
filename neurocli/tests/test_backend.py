"""`neuro backend` parity checks against a stand-in launcher backend."""

from __future__ import annotations

import json
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest
from typer.testing import CliRunner

from neurocli.backend import ROUTES
from neurocli.cli import app

runner = CliRunner()

APP_SOURCE = (
    Path(__file__).resolve().parents[2] / "nmtk" / "neuro_toolkit" / "lib" / "services" / "control_api_service.dart"
)
LAUNCHER_SERVER = Path(__file__).resolve().parents[2] / "nmtk" / "launcher_control" / "http_server.py"


class _Handler(BaseHTTPRequestHandler):
    """Echoes back what it was asked, so tests can assert the wire call."""

    def log_message(self, *_args: object) -> None:
        return

    def _reply(self) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode() if length else ""
        payload = json.dumps(
            {
                "method": self.command,
                "path": self.path,
                "token": self.headers.get("X-NMTK-Admin-Token", ""),
                "body": body,
            }
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST = do_PUT = do_DELETE = _reply


@pytest.fixture()
def fake_backend(monkeypatch):
    server = ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{server.server_address[1]}"
    monkeypatch.setenv("NMTK_LAUNCHER_URL", base)
    monkeypatch.setenv("NMTK_SUITE_API_URL", base)
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "test-token")
    yield base
    server.shutdown()
    server.server_close()


def test_every_route_is_reachable_as_a_command(fake_backend):
    """Each ROUTES entry must run end to end and hit the path it declares."""
    for route in ROUTES:
        if route.stream:
            continue
        values = [f"v{index}" for index, _ in enumerate(route.params)]
        result = runner.invoke(app, ["backend", route.group, route.name, *values, "--json"])
        assert result.exit_code == 0, f"{route.group} {route.name}: {result.output}"
        sent = json.loads(result.stdout)
        expected = route.path
        for name, value in zip(route.params, values, strict=True):
            expected = expected.replace("{" + name + "}", value)
        assert sent["path"] == expected
        assert sent["method"] == route.method
        assert sent["token"] == "test-token"


def test_body_and_query_reach_the_backend(fake_backend):
    result = runner.invoke(
        app,
        ["backend", "modules", "list", "--query", "refreshUpdates=1", "--json"],
    )
    assert result.exit_code == 0
    assert json.loads(result.stdout)["path"] == "/api/launcher/modules?refreshUpdates=1"

    result = runner.invoke(
        app,
        ["backend", "launcher", "set-settings", "--data", '{"theme":"dark"}', "--json"],
    )
    assert result.exit_code == 0
    assert json.loads(json.loads(result.stdout)["body"]) == {"theme": "dark"}


def test_api_escape_hatch(fake_backend):
    result = runner.invoke(app, ["backend", "api", "POST", "/api/launcher/anything", "--json"])
    assert result.exit_code == 0
    assert json.loads(result.stdout)["path"] == "/api/launcher/anything"


def test_missing_path_value_is_a_user_error(fake_backend):
    result = runner.invoke(app, ["backend", "modules", "start", "--json"])
    assert result.exit_code == 1
    assert "wrong_arguments" in result.output


def test_invalid_json_body_is_a_user_error(fake_backend):
    result = runner.invoke(app, ["backend", "launcher", "set-settings", "--data", "{oops", "--json"])
    assert result.exit_code == 1
    assert "invalid_json_body" in result.output


def test_routes_cover_every_launcher_endpoint_the_app_calls():
    """Parity guard: nothing in launcher control is missing from ROUTES."""
    served = set(re.findall(r'path == "(/api/launcher/[^"]+)"', LAUNCHER_SERVER.read_text()))
    covered = {route.path for route in ROUTES}
    assert served - covered == set()


@pytest.mark.skipif(not APP_SOURCE.is_file(), reason="launcher app sources not checked out")
def test_routes_cover_every_endpoint_the_app_uses():
    """Parity guard: every launcher path the Flutter app builds has a command."""
    source = APP_SOURCE.read_text()
    app_paths = {re.sub(r"\$\{?[\w\[\]'.]+\}?", "{x}", raw) for raw in re.findall(r"'(/api/launcher/[^']*)'", source)}
    covered = {re.sub(r"\{\w+\}", "{x}", route.path) for route in ROUTES}
    missing = {path for path in app_paths if path not in covered}
    assert missing == set(), f"App calls endpoints the CLI cannot: {sorted(missing)}"


def test_password_never_reaches_the_ssh_command_line(tmp_path, monkeypatch):
    """The SSH password must travel via SSH_ASKPASS, never argv."""
    from neurocli import session

    recorder = tmp_path / "argv.log"
    stub = tmp_path / "ssh"
    stub.write_text(
        "#!/bin/sh\n"
        f'printf "%s\\n" "$*" >> {recorder}\n'
        f'printf "ASKPASS=%s\\n" "$SSH_ASKPASS" >> {recorder}\n'
        'case "$*" in *"sh -s"*) printf "NMTK_ADMIN_TOKEN|probed\\n";; esac\n'
        "exit 0\n"
    )
    stub.chmod(0o700)
    monkeypatch.setenv("PATH", str(tmp_path))
    monkeypatch.setattr(session, "keychain_read", lambda _account: "hunter2")

    target = session.Target("t", "t", "10.0.0.5", "someone", 22, "ssh_password")
    backend = session._open_tunnel(target)
    try:
        assert backend.admin_token == "probed"
        assert backend.urls["launcher"].startswith("http://127.0.0.1:")
    finally:
        backend.close()

    log = recorder.read_text()
    assert "hunter2" not in log
    assert "ASKPASS=" in log and "askpass" in log
    assert "-L" in log and ":127.0.0.1:8090" in log


def test_askpass_helper_hands_ssh_the_password():
    """The helper ssh runs must print exactly the password it was given."""
    import subprocess

    from neurocli import session

    with session._askpass_dir("hunter2") as directory:
        helper = Path(directory) / "askpass"
        done = subprocess.run(
            [str(helper)],
            env={"NEUROCLI_SSH_PASSWORD": "hunter2"},
            capture_output=True,
            text=True,
            check=True,
        )
    assert done.stdout == "hunter2"


def test_login_json_mode_never_prompts_for_password():
    """`neuro login --json` must fail loudly, not block on getpass in a headless runner."""
    result = runner.invoke(app, ["login", "--target", "someone@10.0.0.5", "--json"])
    assert result.exit_code == 1
    assert "missing_password" in result.output


def test_login_reads_password_from_env(monkeypatch):
    """Headless CI can supply the SSH password via NEUROCLI_SSH_PASSWORD."""
    from neurocli import backend

    saved: list[tuple[str, str]] = []
    monkeypatch.setenv("NEUROCLI_SSH_PASSWORD", "hunter2")
    monkeypatch.setattr(backend, "keychain_write", lambda account, secret: saved.append((account, secret)))
    result = runner.invoke(app, ["login", "--target", "someone@10.0.0.5", "--json"])
    assert result.exit_code == 0, result.output
    assert saved and saved[0] == ("someone@10.0.0.5:22", "hunter2")
