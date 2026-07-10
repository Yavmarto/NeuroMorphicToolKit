"""Launcher control service tests: TestLauncherHardwareRuntimeProxy."""

from pathlib import Path
import json
import nmtk.launcher_control.server as launcher_server
import nmtk.launcher_control.module_install as launcher_module_install
from unittest import mock
import subprocess
import threading
import urllib.request
from base import LauncherControlServiceTestBase


class TestLauncherHardwareRuntimeProxy(LauncherControlServiceTestBase):
    def test_prepare_akida_runtime_marks_unsupported_host_without_installing(self) -> None:
        with (
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_OK,
                    message="ok",
                ),
            ),
            mock.patch.object(launcher_module_install, "_current_platform_key", return_value="macos"),
            mock.patch.object(self.state, "_run_command") as run_command,
        ):
            updated = self.state.prepare_akida_runtime("dummy")

        self.assertEqual(updated["akidaRuntimeState"]["status"], "unsupported_host")
        self.assertIn("Linux or Windows Neurochip host", updated["akidaRuntimeState"]["message"])
        run_command.assert_not_called()

    def test_prepare_akida_runtime_installs_required_packages_on_supported_host(self) -> None:
        commands: list[list[str]] = []

        def fake_run_command(
            command: list[str],
            *,
            cwd: Path,
            module_id: str,
        ) -> subprocess.CompletedProcess[str]:
            commands.append(command)
            if "-c" in command:
                return subprocess.CompletedProcess(command, 0, "3.11.8\n", "")
            return subprocess.CompletedProcess(command, 0, "", "")

        with (
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_OK,
                    message="ok",
                ),
            ),
            mock.patch.object(launcher_module_install, "_current_platform_key", return_value="linux"),
            mock.patch.object(self.state, "_run_command", side_effect=fake_run_command),
        ):
            updated = self.state.prepare_akida_runtime("dummy")

        self.assertEqual(updated["akidaRuntimeState"]["status"], "ready")
        self.assertEqual(len(commands), 2)
        self.assertEqual(commands[1][1:4], ["-m", "pip", "install"])
        self.assertTrue(commands[1][0].endswith("/dummy_module/venv/bin/python"))
        self.assertIn("akida==2.19.1", commands[1])

    def test_modules_endpoint_restores_saved_akida_runtime_state(self) -> None:
        state_file = self.repo_root / "nmtk" / "neuro_toolkit" / "module_states.json"
        state_file.write_text(
            json.dumps(
                {
                    "dummy": {
                        "id": "dummy",
                        "status": launcher_server.STATUS_INDEX["installed"],
                        "installProgress": 1.0,
                        "akidaRuntimeState": {
                            "status": "unsupported_python",
                            "message": (
                                "Akida SDK installation requires Python >=3.10,<3.13; "
                                "current module env is 3.9.18. Keep scaffold export "
                                "local, then verify through a Linux or Windows "
                                "Neurochip host running Python 3.10-3.12."
                            ),
                            "preparedAt": None,
                        },
                    }
                }
            ),
            encoding="utf-8",
        )

        reloaded = launcher_server.LauncherControlState()
        self.addCleanup(reloaded.shutdown)

        payload = reloaded.serialize_module("dummy")
        self.assertEqual(payload["akidaRuntimeState"]["status"], "unsupported_python")
        self.assertIn(
            "Linux or Windows Neurochip host",
            payload["akidaRuntimeState"]["message"],
        )

    def test_prepare_akida_runtime_http_endpoint_returns_remote_host_guidance(self) -> None:
        server = launcher_server.create_server("127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 1.0)

        with (
            mock.patch.object(
                server.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_OK,
                    message="ok",
                ),
            ),
            mock.patch.object(launcher_module_install, "_current_platform_key", return_value="macos"),
        ):
            request = urllib.request.Request(
                (
                    f"http://127.0.0.1:{server.server_address[1]}"
                    "/api/launcher/modules/dummy/akida-runtime/prepare"
                ),
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=5) as response:
                payload = json.loads(response.read().decode("utf-8"))

        self.assertEqual(payload["akidaRuntimeState"]["status"], "unsupported_host")
        self.assertIn(
            "Linux or Windows Neurochip host",
            payload["akidaRuntimeState"]["message"],
        )

    def test_pynq_deploy_http_endpoint_propagates_runtime_422(self) -> None:
        server = launcher_server.create_server("127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 1.0)
        board = server.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.2.99",
                "username": "xilinx",
                "password": "xilinx",
            }
        )
        runtime_body = json.dumps(
            {
                "detail": {
                    "detail": "register_map does not match the installed overlay contract",
                    "error_code": "OVERLAY_REGISTER_MAP_MISMATCH",
                }
            }
        )

        with mock.patch.object(
            server.state,
            "_runtime_json_request",
            side_effect=launcher_server.RuntimeRequestError(
                (
                    "Runtime request failed for POST "
                    "http://192.168.2.99:8002/hardware/pynq/deploy: HTTP 422"
                    f" - {runtime_body}"
                ),
                kind="http",
                url="http://192.168.2.99:8002/hardware/pynq/deploy",
                status_code=422,
                response_body=runtime_body,
            ),
        ):
            request = urllib.request.Request(
                (
                    f"http://127.0.0.1:{server.server_address[1]}"
                    f"/api/launcher/pynq/boards/{board['id']}/deploy"
                ),
                data=json.dumps({"weights": [1.0]}).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as exc_info:
                urllib.request.urlopen(request, timeout=5)

        self.assertEqual(exc_info.exception.code, 422)
        payload = json.loads(exc_info.exception.read().decode("utf-8"))
        self.assertEqual(
            payload["runtimeJson"]["detail"]["error_code"],
            "OVERLAY_REGISTER_MAP_MISMATCH",
        )
        self.assertIn("OVERLAY_REGISTER_MAP_MISMATCH", payload["runtimeBody"])

    def test_pynq_deploy_http_endpoint_reports_unreachable_runtime_as_bad_gateway(
        self,
    ) -> None:
        server = launcher_server.create_server("127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 1.0)
        board = server.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.2.51",
                "username": "xilinx",
                "password": "xilinx",
            }
        )

        with mock.patch.object(
            server.state,
            "_runtime_json_request",
            side_effect=launcher_server.RuntimeRequestError(
                (
                    "Runtime request failed for POST "
                    "http://192.168.2.51:8002/hardware/pynq/deploy: "
                    "could not be reached: <urlopen error [Errno 61] Connection refused>"
                ),
                kind="unreachable",
                url="http://192.168.2.51:8002/hardware/pynq/deploy",
            ),
        ):
            request = urllib.request.Request(
                (
                    f"http://127.0.0.1:{server.server_address[1]}"
                    f"/api/launcher/pynq/boards/{board['id']}/deploy"
                ),
                data=json.dumps({"weights": [1.0]}).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as exc_info:
                urllib.request.urlopen(request, timeout=5)

        self.assertEqual(exc_info.exception.code, 502)
        payload = json.loads(exc_info.exception.read().decode("utf-8"))
        self.assertIn("192.168.2.51:8002", payload["error"])
        self.assertIn("Connection refused", payload["error"])

    def test_pynq_run_http_endpoint_proxies_runtime_payload(self) -> None:
        server = launcher_server.create_server("127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 1.0)
        board = server.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.2.77",
                "username": "xilinx",
                "password": "xilinx",
            }
        )

        with mock.patch.object(
            server.state,
            "_runtime_json_request",
            return_value={
                "status": "success",
                "output_spikes": [0, 2],
                "timesteps": 2,
                "execution_time_us": 18.5,
            },
        ) as runtime_request:
            request = urllib.request.Request(
                (
                    f"http://127.0.0.1:{server.server_address[1]}"
                    f"/api/launcher/pynq/boards/{board['id']}/run"
                ),
                data=json.dumps({"input_spikes": [0, 1], "timesteps": 2}).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=5) as response:
                payload = json.loads(response.read().decode("utf-8"))

        self.assertEqual(payload["status"], "success")
        self.assertEqual(payload["output_spikes"], [0, 2])
        runtime_request.assert_called_once()
        called_board, called_method, called_path, called_payload = runtime_request.call_args.args
        self.assertEqual(called_board["id"], board["id"])
        self.assertEqual(called_method, "POST")
        self.assertEqual(called_path, "/hardware/pynq/run")
        self.assertEqual(called_payload, {"input_spikes": [0, 1], "timesteps": 2})

    def test_proxy_akida_map_proxies_runtime_payload(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "192.168.2.88",
                "username": "operator",
                "password": "secret",
                "runtimeApiUrl": "http://192.168.2.88:8002",
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={
                "sdk_available": True,
                "sdk_status": "deployable",
                "sdk_issues": [],
                "state": "mapped",
                "runtime_target": "hardware",
                "environment_checks": {
                    "host_supported": True,
                    "python_supported": True,
                    "tensorflow_available": True,
                    "cnn2snn_available": True,
                    "akida_models_available": True,
                    "recommended_runtime": "remote_sdk",
                },
            },
        ) as runtime_request:
            payload = self.state.proxy_akida_map(
                host["id"],
                {
                    "akida_version": "akida2",
                    "populations": [{"id": "sensor", "size": 4}],
                    "connections": [],
                },
                bit_width=2,
            )

        self.assertEqual(payload["runtime_target"], "hardware")
        runtime_request.assert_called_once()
        called_host, called_method, called_path, called_payload = runtime_request.call_args.args
        self.assertEqual(called_host["id"], host["id"])
        self.assertEqual(called_method, "POST")
        self.assertEqual(called_path, "/api/neurochip/akida/map?bit_width=2")
        self.assertEqual(
            called_payload,
            {
                "akida_version": "akida2",
                "populations": [{"id": "sensor", "size": 4}],
                "connections": [],
            },
        )

    def test_akida_map_http_endpoint_proxies_runtime_payload(self) -> None:
        server = launcher_server.create_server("127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 1.0)
        host = server.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "192.168.2.88",
                "username": "operator",
                "password": "secret",
                "runtimeApiUrl": "http://192.168.2.88:8002",
            }
        )

        with mock.patch.object(
            server.state,
            "proxy_akida_map",
            return_value={
                "sdk_available": True,
                "sdk_status": "deployable",
                "sdk_issues": [],
                "state": "mapped",
                "runtime_target": "hardware",
            },
        ) as proxy_map:
            request = urllib.request.Request(
                (
                    f"http://127.0.0.1:{server.server_address[1]}"
                    f"/api/launcher/akida/hosts/{host['id']}/map?bit_width=2"
                ),
                data=json.dumps(
                    {
                        "akida_version": "akida2",
                        "populations": [{"id": "sensor", "size": 4}],
                        "connections": [],
                    }
                ).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=5) as response:
                payload = json.loads(response.read().decode("utf-8"))

        self.assertEqual(payload["runtime_target"], "hardware")
        proxy_map.assert_called_once_with(
            host["id"],
            {
                "akida_version": "akida2",
                "populations": [{"id": "sensor", "size": 4}],
                "connections": [],
            },
            bit_width=2,
        )

    def test_proxy_akida_run_proxies_runtime_payload(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "192.168.2.89",
                "username": "operator",
                "password": "secret",
                "runtimeApiUrl": "http://192.168.2.89:8002",
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={
                "outputs": [0.0, 1.0],
                "telemetry": {"fps": 123.0},
                "execution_time_us": 4.2,
                "runtime_target": "hardware",
            },
        ) as runtime_request:
            payload = self.state.proxy_akida_run(
                host["id"],
                {"inputs": [1.0, 0.0, 1.0]},
            )

        self.assertEqual(payload["runtime_target"], "hardware")
        self.assertEqual(payload["outputs"], [0.0, 1.0])
        runtime_request.assert_called_once()
        called_host, called_method, called_path, called_payload = runtime_request.call_args.args
        self.assertEqual(called_host["id"], host["id"])
        self.assertEqual(called_method, "POST")
        self.assertEqual(called_path, "/api/neurochip/akida/inference")
        self.assertEqual(called_payload, {"inputs": [1.0, 0.0, 1.0]})

    def test_akida_run_http_endpoint_proxies_runtime_payload(self) -> None:
        server = launcher_server.create_server("127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 1.0)
        host = server.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "192.168.2.89",
                "username": "operator",
                "password": "secret",
                "runtimeApiUrl": "http://192.168.2.89:8002",
            }
        )

        with mock.patch.object(
            server.state,
            "proxy_akida_run",
            return_value={
                "outputs": [0.0, 1.0],
                "telemetry": {"fps": 123.0},
                "execution_time_us": 4.2,
                "runtime_target": "hardware",
            },
        ) as proxy_run:
            request = urllib.request.Request(
                (
                    f"http://127.0.0.1:{server.server_address[1]}"
                    f"/api/launcher/akida/hosts/{host['id']}/run"
                ),
                data=json.dumps({"inputs": [1.0, 0.0, 1.0]}).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=5) as response:
                payload = json.loads(response.read().decode("utf-8"))

        self.assertEqual(payload["runtime_target"], "hardware")
        self.assertEqual(payload["outputs"], [0.0, 1.0])
        proxy_run.assert_called_once_with(
            host["id"],
            {"inputs": [1.0, 0.0, 1.0]},
        )
