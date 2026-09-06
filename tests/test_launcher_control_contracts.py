"""Compatibility contracts for the launcher-control façade and transport."""

from __future__ import annotations

import io
import json
import os
import unittest
from http import HTTPStatus
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest import mock

from nmtk.launcher_control import server
from nmtk.launcher_control.http_transport import read_json_body, send_json
from nmtk.launcher_control.runtime_contracts import (
    PynqLauncherRuntimeContract,
    load_neurochip_launcher_runtime_contract,
)
from nmtk.launcher_control.runtime_errors import RuntimeRequestError


class _TransportHandler:
    def __init__(self, body: bytes = b"", origin: str = "") -> None:
        self.headers = {"Content-Length": str(len(body)), "Origin": origin}
        self.rfile = io.BytesIO(body)
        self.wfile = io.BytesIO()
        self.responses: list[int] = []
        self.response_headers: dict[str, str] = {}

    def send_response(self, status: int) -> None:
        self.responses.append(status)

    def send_header(self, key: str, value: str) -> None:
        self.response_headers[key] = value

    def end_headers(self) -> None:
        pass


class _RouteHandler:
    def __init__(self, path: str, state: object) -> None:
        self.path = path
        self.headers: dict[str, str] = {}
        self.server = SimpleNamespace(state=state)
        self.responses: list[tuple[HTTPStatus, object]] = []

    def _read_body(self) -> None:
        return None

    def _send_json(self, status: HTTPStatus, payload: object) -> None:
        self.responses.append((status, payload))


class LauncherControlContractTest(unittest.TestCase):
    def test_server_reexports_extracted_runtime_contracts_and_error(self) -> None:
        self.assertIs(server.PynqLauncherRuntimeContract, PynqLauncherRuntimeContract)
        self.assertIs(server.RuntimeRequestError, RuntimeRequestError)

    def test_contract_loader_uses_manifest_values_and_safe_defaults(self) -> None:
        with TemporaryDirectory() as temp_dir:
            manifest_path = Path(temp_dir) / "modules.json"
            manifest_path.write_text(
                json.dumps(
                    [{"id": "Neurochip", "launcherRuntime": {"pynq": {"sshPort": 2222}}}]
                ),
                encoding="utf-8",
            )
            contract = load_neurochip_launcher_runtime_contract(manifest_path)
        self.assertEqual(contract.pynq.ssh_port, 2222)
        self.assertEqual(contract.pynq.runtime_port, 8002)

    def test_transport_preserves_object_only_body_and_cors_contract(self) -> None:
        handler = _TransportHandler(
            b'{"enabled": true}', origin="https://allowed.example"
        )
        self.assertEqual(read_json_body(handler), {"enabled": True})
        with mock.patch.dict(
            os.environ, {"NMTK_ALLOWED_ORIGINS": "https://allowed.example"}
        ):
            send_json(handler, HTTPStatus.OK, {"status": "ok"})
        self.assertEqual(handler.responses, [HTTPStatus.OK])
        self.assertEqual(
            handler.response_headers["Access-Control-Allow-Origin"],
            "https://allowed.example",
        )
        self.assertEqual(handler.response_headers["Vary"], "Origin")
        self.assertEqual(
            json.loads(handler.wfile.getvalue().decode("utf-8")), {"status": "ok"}
        )

    def test_routes_normalize_trailing_slash_and_preserve_runtime_error_mapping(self) -> None:
        state = SimpleNamespace(
            get_settings=lambda: {"controlLogLevel": "info"},
            proxy_pynq_deploy=lambda _board, _body: (_ for _ in ()).throw(
                RuntimeRequestError(
                    "runtime rejected payload",
                    kind="http",
                    url="http://runtime/deploy",
                    status_code=422,
                    response_body='{"detail":"invalid"}',
                )
            ),
        )
        health = _RouteHandler("/health/", state)
        server.LauncherControlHandler._dispatch(health, "GET")
        self.assertEqual(health.responses, [(HTTPStatus.OK, {"status": "ok", "controlLogLevel": "info"})])

        deploy = _RouteHandler("/api/launcher/pynq/boards/demo/deploy", state)
        server.LauncherControlHandler._dispatch(deploy, "POST")
        status, payload = deploy.responses[0]
        self.assertEqual(status, HTTPStatus.UNPROCESSABLE_ENTITY)
        self.assertEqual(payload["runtimeJson"], {"detail": "invalid"})

        unknown = _RouteHandler("/api/launcher/not-real/", state)
        server.LauncherControlHandler._dispatch(unknown, "GET")
        self.assertEqual(unknown.responses[0][0], HTTPStatus.NOT_FOUND)
