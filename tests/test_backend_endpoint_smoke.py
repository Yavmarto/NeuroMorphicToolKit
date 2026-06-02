from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from typing import Any

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "backend_endpoint_smoke.py"
SPEC = importlib.util.spec_from_file_location("backend_endpoint_smoke", SCRIPT_PATH)
assert SPEC is not None
backend_endpoint_smoke = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = backend_endpoint_smoke
SPEC.loader.exec_module(backend_endpoint_smoke)


class FakeHTTPResponse:
    def __init__(self, status: int, payload: bytes) -> None:
        self.status = status
        self._payload = payload
        self.headers: dict[str, str] = {"content-type": "application/json"}

    def __enter__(self) -> "FakeHTTPResponse":
        return self

    def __exit__(self, *_args: Any) -> None:
        return None

    def read(self) -> bytes:
        return self._payload

    def getcode(self) -> int:
        return self.status


class BackendEndpointSmokeTests(unittest.TestCase):
    def _write_manifest(self, root: Path) -> Path:
        manifest = [
            {
                "id": "neurocnl",
                "name": "CNL Studio",
                "port": 8000,
                "installPath": "neurocnl/",
                "sourcePath": ".",
                "runPath": ".",
                "startStrategy": "uvicorn",
                "uvicornTarget": "backend.app.main:app",
            },
            {
                "id": "cli_only_stub",
                "name": "CLI-only stub",
                "port": None,
                "installPath": "examples/cli-only/",
                "sourcePath": ".",
                "runPath": ".",
                "startStrategy": "none",
                "uvicornTarget": "",
            },
        ]
        manifest_path = root / "modules.json"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        return manifest_path

    def test_load_manifest_filters_runnable_modules(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest_path = self._write_manifest(Path(tmp))

            modules = backend_endpoint_smoke.load_manifest(manifest_path)
            runnable = backend_endpoint_smoke.runnable_modules(modules)

        self.assertEqual([module.id for module in modules], ["neurocnl", "cli_only_stub"])
        self.assertEqual([module.id for module in runnable], ["neurocnl"])

    def test_find_module_and_base_url_are_manifest_driven(self) -> None:
        module = backend_endpoint_smoke.ModuleSpec.from_manifest(
            {
                "id": "Neurochip",
                "port": 8002,
                "installPath": "Neurochip/",
                "uvicornTarget": "neurochip.app.main:app",
            }
        )

        found = backend_endpoint_smoke.find_module("neurochip", [module])
        base_url = backend_endpoint_smoke.module_base_url(found)

        self.assertEqual(found.id, "Neurochip")
        self.assertEqual(base_url, "http://127.0.0.1:8002")

    def test_build_uvicorn_command_uses_manifest_paths_and_venv_python(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            module_dir = root / "neurocnl"
            python_path = module_dir / ".venv" / "bin" / "python"
            python_path.parent.mkdir(parents=True)
            python_path.touch()
            module = backend_endpoint_smoke.ModuleSpec.from_manifest(
                {
                    "id": "neurocnl",
                    "port": 8000,
                    "installPath": "neurocnl/",
                    "sourcePath": ".",
                    "runPath": ".",
                    "uvicornTarget": "backend.app.main:app",
                }
            )

            command, run_dir = backend_endpoint_smoke.build_uvicorn_command(module, root)

        self.assertEqual(command[0], str(python_path.resolve()))
        self.assertEqual(command[1:4], ["-m", "uvicorn", "backend.app.main:app"])
        self.assertIn("--host", command)
        self.assertIn("--port", command)
        self.assertEqual(command[command.index("--port") + 1], "8000")
        self.assertEqual(run_dir, module_dir.resolve())

    def test_parse_json_arg_accepts_inline_and_file_payloads(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload_path = Path(tmp) / "payload.json"
            payload_path.write_text('{"from_file": true}', encoding="utf-8")

            inline = backend_endpoint_smoke.parse_json_arg('{"inline": true}')
            from_file = backend_endpoint_smoke.parse_json_arg(f"@{payload_path}")

        self.assertEqual(inline, {"inline": True})
        self.assertEqual(from_file, {"from_file": True})

    def test_parse_json_arg_rejects_invalid_json(self) -> None:
        with self.assertRaises(backend_endpoint_smoke.SmokeError):
            backend_endpoint_smoke.parse_json_arg("{bad json")

    def test_http_request_sends_json_and_validates_success(self) -> None:
        captured: dict[str, Any] = {}

        def opener(request: Any, timeout: float) -> FakeHTTPResponse:
            captured["url"] = request.full_url
            captured["method"] = request.get_method()
            captured["data"] = request.data
            captured["timeout"] = timeout
            return FakeHTTPResponse(200, b'{"ok": true}')

        response = backend_endpoint_smoke.http_request(
            "http://127.0.0.1:8000/api/test",
            method="POST",
            payload={"hello": "world"},
            timeout=2.0,
            opener=opener,
        )
        backend_endpoint_smoke.require_success(response, "http://127.0.0.1:8000/api/test")

        self.assertEqual(response.status, 200)
        self.assertEqual(response.json(), {"ok": True})
        self.assertEqual(captured["method"], "POST")
        self.assertEqual(json.loads(captured["data"].decode("utf-8")), {"hello": "world"})
        self.assertEqual(captured["timeout"], 2.0)

    def test_http_error_can_be_allowed_or_rejected(self) -> None:
        def opener(_request: Any, timeout: float) -> FakeHTTPResponse:
            self.assertGreater(timeout, 0)
            raise urllib.error.HTTPError(
                "http://127.0.0.1:8000/api/test",
                422,
                "Unprocessable Entity",
                {},
                io.BytesIO(b'{"detail": "bad payload"}'),
            )

        response = backend_endpoint_smoke.http_request(
            "http://127.0.0.1:8000/api/test",
            method="POST",
            payload={"bad": True},
            opener=opener,
        )

        with self.assertRaises(backend_endpoint_smoke.SmokeError):
            backend_endpoint_smoke.require_success(response, "http://127.0.0.1:8000/api/test")
        backend_endpoint_smoke.require_success(
            response,
            "http://127.0.0.1:8000/api/test",
            allow_statuses={422},
        )


if __name__ == "__main__":
    unittest.main()
