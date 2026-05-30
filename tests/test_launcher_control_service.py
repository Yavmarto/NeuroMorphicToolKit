import io
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.request
from pathlib import Path
from typing import Any
from unittest import mock

import nmtk.launcher_control.provisioning_helpers as provisioning_helpers
import nmtk.launcher_control.server as launcher_server

PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _stage_overlay_package(staging_dir: Path) -> None:
    staging_dir.mkdir(parents=True, exist_ok=True)
    (staging_dir / "snn_overlay.bit").write_bytes(b"bitstream")
    (staging_dir / "snn_overlay.hwh").write_text("<hwh/>", encoding="utf-8")
    (staging_dir / "overlay_manifest.json").write_text(
        json.dumps(
            {
                "overlay_id": "snn_overlay_v1",
                "overlay_version": "1.0.1",
                "target_part": "xc7z020clg400-1",
                "supported_neuron_models": ["LIF"],
                "supported_weight_bit_widths": [8],
                "max_neurons": 256,
                "max_synapses": 15360,
                "max_populations": 2,
                "dma_ip_name": "axi_dma_0",
                "snn_ip_name": "snn_engine_0",
                "register_map": {
                    "base_address": 1073741824,
                    "control_reg_offset": 0,
                    "status_reg_offset": 4,
                    "population_count_offset": 8,
                    "input_neuron_count_offset": 12,
                    "output_neuron_count_offset": 16,
                    "timestep_count_offset": 20,
                    "threshold_base_offset": 256,
                    "neuron_base_offset": 256,
                    "weight_base_offset": 4096,
                    "dma_channel": "axi_dma_0",
                    "input_buffer_addr": 0,
                    "output_buffer_addr": 0,
                    "timestep_us": 1000,
                },
                "weight_layout": {
                    "format": "int8_dense_row_major_word_mmio",
                    "storage": "mmio",
                    "base_offset": 4096,
                    "stride_bytes": 4,
                    "max_entries": 15360,
                },
                "threshold_layout": {
                    "format": "float32_per_population",
                    "storage": "mmio",
                    "base_offset": 256,
                    "stride_bytes": 4,
                    "max_entries": 2,
                },
            },
            indent=2,
        ),
        encoding="utf-8",
    )


class LauncherControlServiceTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tempdir = tempfile.TemporaryDirectory()
        self.repo_root = Path(self._tempdir.name) / "repo"
        assets_dir = self.repo_root / "nmtk" / "neuro_toolkit" / "assets"
        assets_dir.mkdir(parents=True, exist_ok=True)
        (self.repo_root / "dummy_module").mkdir(parents=True, exist_ok=True)
        self._resolved_versions: dict[str, str | None] = {"dummy": None}
        self._resolver_calls: list[str] = []

        (assets_dir / "modules.json").write_text(
            json.dumps(
                [
                    {
                        "id": "dummy",
                        "name": "Dummy Module",
                        "description": "Used for launcher control tests",
                        "icon": "extension",
                        "port": 8123,
                        "installPath": "dummy_module",
                        "sourcePath": ".",
                        "runPath": ".",
                        "uvicornTarget": "app.main:app",
                        "hasFrontend": True,
                        "frontendStatus": "Yes",
                        "requiresMuJoCo": False,
                        "version": "1.0.0",
                        "remoteUrl": "https://api.github.com/repos/example/dummy",
                        "akidaRuntime": {
                            "supportedPlatforms": ["linux", "windows"],
                            "pythonRange": ">=3.10,<3.13",
                            "requiredPackages": [
                                "tensorflow==2.19.*",
                                "akida==2.19.1",
                                "cnn2snn==2.19.1",
                                "akida-models==1.13.1",
                            ],
                            "docsUrl": "https://doc.brainchipinc.com/installation.html",
                            "localModeFallback": "simulator_only",
                        },
                    }
                ]
            ),
            encoding="utf-8",
        )

        self._patches = [
            mock.patch.object(launcher_server, "REPO_ROOT", self.repo_root),
            mock.patch.object(
                launcher_server,
                "MODULES_MANIFEST",
                assets_dir / "modules.json",
            ),
            mock.patch.object(
                launcher_server,
                "STATE_FILE",
                self.repo_root / "nmtk" / "neuro_toolkit" / "module_states.json",
            ),
            mock.patch.object(
                launcher_server,
                "SETTINGS_FILE",
                self.repo_root / "nmtk" / "neuro_toolkit" / "launcher_settings.json",
            ),
            mock.patch.object(
                launcher_server,
                "WORKSPACE_FILE",
                self.repo_root / "nmtk" / "neuro_toolkit" / "workspace_state.json",
            ),
            mock.patch.object(
                launcher_server,
                "DEPLOYMENT_STATE_FILE",
                self.repo_root / "nmtk" / "neuro_toolkit" / "deployment_state.json",
            ),
            mock.patch.object(
                launcher_server,
                "DEPLOYMENT_SECRET_FILE",
                self.repo_root / ".nmtk" / "deployment_secrets.json",
            ),
        ]
        for patcher in self._patches:
            patcher.start()
            self.addCleanup(patcher.stop)

        self.state = launcher_server.LauncherControlState(
            remote_version_resolver=self._resolve_remote_version
        )
        self._fake_venv_python = self._create_fake_venv_python()

    def tearDown(self) -> None:
        self.state.shutdown()
        self._tempdir.cleanup()

    def _create_fake_venv_python(self) -> Path:
        python_path = self.repo_root / "dummy_module" / "venv" / "bin" / "python"
        python_path.parent.mkdir(parents=True, exist_ok=True)
        python_path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        python_path.chmod(0o755)
        return python_path

    def _create_fake_poetry_python(self) -> Path:
        python_path = (
            self.repo_root
            / ".poetry-envs"
            / "dummy"
            / "bin"
            / "python"
        )
        python_path.parent.mkdir(parents=True, exist_ok=True)
        python_path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        python_path.chmod(0o755)
        return python_path

    def _write_poetry_pyproject(self) -> None:
        pyproject = self.repo_root / "dummy_module" / "pyproject.toml"
        pyproject.write_text(
            "\n".join(
                [
                    "[tool.poetry]",
                    'name = "dummy"',
                    'version = "0.1.0"',
                    "",
                    "[build-system]",
                    'requires = ["poetry-core>=1.0.0"]',
                    'build-backend = "poetry.core.masonry.api"',
                ]
            ),
            encoding="utf-8",
        )

    def _create_fake_inproject_poetry_python_symlink(self) -> tuple[Path, Path]:
        python_path = self.repo_root / "dummy_module" / ".venv" / "bin" / "python"
        base_python = self.repo_root / "python-base" / "bin" / "python"
        python_path.parent.mkdir(parents=True, exist_ok=True)
        base_python.parent.mkdir(parents=True, exist_ok=True)
        base_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        base_python.chmod(0o755)
        python_path.symlink_to(base_python)
        return python_path, base_python

    def _resolve_remote_version(self, module: dict[str, Any]) -> str | None:
        module_id = str(module["id"])
        self._resolver_calls.append(module_id)
        return self._resolved_versions.get(module_id)

    def _reload_state_with_modules(self, modules: list[dict[str, Any]]) -> None:
        manifest_path = self.repo_root / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
        manifest_path.write_text(json.dumps(modules), encoding="utf-8")
        self.state.shutdown()
        self.state = launcher_server.LauncherControlState(
            remote_version_resolver=self._resolve_remote_version
        )

    def test_modules_endpoint_returns_manifest_data(self) -> None:
        payload = self.state.serialize_modules()

        self.assertIsInstance(payload, list)
        self.assertEqual(payload[0]["id"], "dummy")
        self.assertEqual(payload[0]["remoteVersion"], "1.0.0")
        self.assertEqual(
            payload[0]["status"],
            launcher_server.STATUS_INDEX["notInstalled"],
        )
        self.assertEqual(
            payload[0]["akidaRuntime"]["localModeFallback"],
            "simulator_only",
        )
        self.assertEqual(self._resolver_calls, [])

    def test_serialize_modules_refresh_updates_uses_remote_version_resolver(self) -> None:
        self._resolved_versions["dummy"] = "1.2.0"

        payload = self.state.serialize_modules(refresh_updates=True)

        self.assertEqual(payload[0]["remoteVersion"], "1.2.0")
        self.assertEqual(self._resolver_calls, ["dummy"])

    def test_refresh_remote_versions_ignores_older_versions(self) -> None:
        self._resolved_versions["dummy"] = "0.9.0"

        payload = self.state.serialize_modules(refresh_updates=True)

        self.assertEqual(payload[0]["remoteVersion"], "1.0.0")

    def test_refresh_remote_versions_keeps_last_known_update_when_lookup_fails(self) -> None:
        self._resolved_versions["dummy"] = "1.2.0"
        self.state.serialize_modules(refresh_updates=True)
        self._resolved_versions["dummy"] = None

        payload = self.state.serialize_modules(refresh_updates=True)

        self.assertEqual(payload[0]["remoteVersion"], "1.2.0")

    def test_pinned_modules_do_not_surface_remote_updates(self) -> None:
        self.state.update_module_settings("dummy", {"versionPinned": True})
        self._resolved_versions["dummy"] = "1.3.0"

        payload = self.state.serialize_modules(refresh_updates=True)

        self.assertTrue(payload[0]["versionPinned"])
        self.assertEqual(payload[0]["remoteVersion"], "1.0.0")

    def test_suite_api_python_reinstalls_when_venv_is_recreated(self) -> None:
        suite_api_dir = self.repo_root / "suite_api"
        suite_api_dir.mkdir(parents=True, exist_ok=True)

        env_dir = self.repo_root / ".nmtk" / "suite_api_env"
        env_dir.mkdir(parents=True, exist_ok=True)
        stamp_path = launcher_server._suite_api_env_stamp(env_dir)
        fingerprint = "test-fingerprint"
        stamp_path.write_text(
            json.dumps({"fingerprint": fingerprint}),
            encoding="utf-8",
        )

        install_targets: list[str] = []

        def fake_run(cmd: list[str], **kwargs: Any) -> mock.Mock:
            args = [str(part) for part in cmd]
            if args[:3] == [sys.executable, "-m", "venv"]:
                venv_python = launcher_server._suite_api_env_python(env_dir)
                venv_python.parent.mkdir(parents=True, exist_ok=True)
                venv_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
                venv_python.chmod(0o755)
                return mock.Mock(returncode=0, stdout="", stderr="")
            if len(args) >= 5 and args[1:4] == ["-m", "pip", "install"]:
                install_targets.append(args[-1])
                return mock.Mock(returncode=0, stdout="", stderr="")
            self.fail(f"Unexpected subprocess.run call: {args}")

        with (
            mock.patch.dict(os.environ, {"NMTK_SUITE_API_ENV_DIR": str(env_dir)}, clear=False),
            mock.patch.object(
                launcher_server,
                "_suite_api_env_fingerprint",
                return_value=fingerprint,
            ),
            mock.patch.object(
                launcher_server,
                "_suite_api_dev_install_paths",
                return_value=(suite_api_dir,),
            ),
            mock.patch("nmtk.launcher_control.server.subprocess.run", side_effect=fake_run),
        ):
            python_path = self.state._suite_api_python()

        self.assertTrue(python_path.endswith("venv/bin/python"))
        self.assertEqual(install_targets, [str(suite_api_dir)])

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
            mock.patch.object(launcher_server, "_current_platform_key", return_value="macos"),
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
            mock.patch.object(launcher_server, "_current_platform_key", return_value="linux"),
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
            mock.patch.object(launcher_server, "_current_platform_key", return_value="macos"),
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

    def test_missing_environment_normalizes_stale_installed_state(self) -> None:
        state_file = self.repo_root / "nmtk" / "neuro_toolkit" / "module_states.json"
        state_file.write_text(
            json.dumps(
                {
                    "dummy": {
                        "id": "dummy",
                        "status": launcher_server.STATUS_INDEX["installed"],
                        "installProgress": 1.0,
                        "environmentFingerprint": None,
                    }
                }
            ),
            encoding="utf-8",
        )
        self._fake_venv_python.unlink()

        reloaded = launcher_server.LauncherControlState(
            remote_version_resolver=self._resolve_remote_version
        )
        self.addCleanup(reloaded.shutdown)

        payload = reloaded.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["notInstalled"])
        self.assertEqual(payload["installProgress"], 0.0)

    def test_module_settings_round_trip_updates_state_file(self) -> None:
        updated = self.state.update_module_settings(
            "dummy",
            {"customPort": 9001, "isEnabled": False, "versionPinned": True},
        )

        self.assertEqual(updated["customPort"], 9001)
        self.assertFalse(updated["isEnabled"])
        self.assertTrue(updated["versionPinned"])

        persisted = json.loads(
            (
                self.repo_root
                / "nmtk"
                / "neuro_toolkit"
                / "module_states.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(persisted["dummy"]["customPort"], 9001)
        self.assertFalse(persisted["dummy"]["isEnabled"])
        self.assertTrue(persisted["dummy"]["versionPinned"])

    def test_workspace_session_round_trip_updates_workspace_file(self) -> None:
        created = self.state.create_workspace_session(
            {
                "moduleId": "dummy",
                "surfaceMode": "native",
                "deepLink": "/deploy",
                "restoreState": {"panel": "validation"},
                "readinessState": "restoring_session",
            }
        )

        self.assertEqual(created["focusedModuleId"], "dummy")
        self.assertEqual(len(created["sessions"]), 1)
        self.assertEqual(created["sessions"][0]["surfaceMode"], "native")
        self.assertEqual(created["sessions"][0]["deepLink"], "/deploy")

        persisted = json.loads(
            (
                self.repo_root
                / "nmtk"
                / "neuro_toolkit"
                / "workspace_state.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(persisted["focusedModuleId"], "dummy")
        self.assertEqual(persisted["sessions"][0]["restoreState"]["panel"], "validation")

    def test_workspace_update_normalizes_missing_focus(self) -> None:
        self.state.create_workspace_session({"moduleId": "dummy"})

        updated = self.state.update_workspace(
            {
                "sessions": [],
                "focusedModuleId": None,
            }
        )

        self.assertEqual(updated["sessions"], [])
        self.assertIsNone(updated["focusedModuleId"])

    def test_workspace_reload_restores_saved_sessions(self) -> None:
        workspace_file = self.repo_root / "nmtk" / "neuro_toolkit" / "workspace_state.json"
        workspace_file.write_text(
            json.dumps(
                {
                    "sessions": [
                        {
                            "moduleId": "dummy",
                            "surfaceMode": "native",
                            "deepLink": "/analysis",
                            "restoreState": {"tab": "energy"},
                            "readinessState": "ready",
                        }
                    ],
                    "focusedModuleId": "dummy",
                }
            ),
            encoding="utf-8",
        )

        reloaded = launcher_server.LauncherControlState(
            remote_version_resolver=self._resolve_remote_version
        )
        self.addCleanup(reloaded.shutdown)

        workspace = reloaded.get_workspace()
        self.assertEqual(workspace["focusedModuleId"], "dummy")
        self.assertEqual(workspace["sessions"][0]["deepLink"], "/analysis")
        self.assertEqual(workspace["sessions"][0]["restoreState"]["tab"], "energy")

    def test_workspace_session_normalizes_legacy_neurosim_module_and_deep_link(self) -> None:
        self._reload_state_with_modules(
            [
                {
                    "id": "dummy",
                    "name": "Dummy Module",
                    "description": "Used for launcher control tests",
                    "icon": "extension",
                    "port": 8123,
                    "installPath": "dummy_module",
                    "sourcePath": ".",
                    "runPath": ".",
                    "uvicornTarget": "app.main:app",
                    "hasFrontend": True,
                    "frontendStatus": "Yes",
                    "requiresMuJoCo": False,
                    "version": "1.0.0",
                    "remoteUrl": "https://api.github.com/repos/example/dummy",
                },
                {
                    "id": "neurocnl",
                    "name": "NeuroStudio",
                    "description": "CNL and canvas authoring",
                    "icon": "code",
                    "port": 8000,
                    "installPath": "neurocnl",
                    "sourcePath": ".",
                    "runPath": ".",
                    "uvicornTarget": "backend.app.main:app",
                    "hasFrontend": True,
                    "frontendStatus": "Yes",
                    "requiresMuJoCo": False,
                    "version": "0.6.0",
                    "remoteUrl": "https://api.github.com/repos/example/neurocnl",
                },
            ]
        )

        created = self.state.create_workspace_session(
            {
                "moduleId": "Neurosim",
                "surfaceMode": "native",
                "deepLink": "/projects?view=recent",
                "restoreState": {"tab": "canvas"},
                "readinessState": "restoring_session",
            }
        )

        self.assertEqual(created["focusedModuleId"], "neurocnl")
        self.assertEqual(len(created["sessions"]), 1)
        self.assertEqual(created["sessions"][0]["moduleId"], "neurocnl")
        self.assertEqual(created["sessions"][0]["surfaceMode"], "native")
        self.assertEqual(created["sessions"][0]["deepLink"], "/canvas/projects?view=recent")

    def test_workspace_reload_normalizes_legacy_neurosim_focus_and_canvas_routes(self) -> None:
        self._reload_state_with_modules(
            [
                {
                    "id": "dummy",
                    "name": "Dummy Module",
                    "description": "Used for launcher control tests",
                    "icon": "extension",
                    "port": 8123,
                    "installPath": "dummy_module",
                    "sourcePath": ".",
                    "runPath": ".",
                    "uvicornTarget": "app.main:app",
                    "hasFrontend": True,
                    "frontendStatus": "Yes",
                    "requiresMuJoCo": False,
                    "version": "1.0.0",
                    "remoteUrl": "https://api.github.com/repos/example/dummy",
                },
                {
                    "id": "neurocnl",
                    "name": "NeuroStudio",
                    "description": "CNL and canvas authoring",
                    "icon": "code",
                    "port": 8000,
                    "installPath": "neurocnl",
                    "sourcePath": ".",
                    "runPath": ".",
                    "uvicornTarget": "backend.app.main:app",
                    "hasFrontend": True,
                    "frontendStatus": "Yes",
                    "requiresMuJoCo": False,
                    "version": "0.6.0",
                    "remoteUrl": "https://api.github.com/repos/example/neurocnl",
                },
            ]
        )

        workspace_file = self.repo_root / "nmtk" / "neuro_toolkit" / "workspace_state.json"
        workspace_file.write_text(
            json.dumps(
                {
                    "sessions": [
                        {
                            "moduleId": "Neurosim",
                            "surfaceMode": "native",
                            "deepLink": "/export?target=python",
                            "restoreState": {"tab": "export"},
                            "readinessState": "ready",
                        }
                    ],
                    "focusedModuleId": "Neurosim",
                }
            ),
            encoding="utf-8",
        )

        reloaded = launcher_server.LauncherControlState(
            remote_version_resolver=self._resolve_remote_version
        )
        self.addCleanup(reloaded.shutdown)

        workspace = reloaded.get_workspace()
        self.assertEqual(workspace["focusedModuleId"], "neurocnl")
        self.assertEqual(workspace["sessions"][0]["moduleId"], "neurocnl")
        self.assertEqual(workspace["sessions"][0]["deepLink"], "/canvas/export?target=python")

    def test_akida_host_round_trip_updates_settings_file(self) -> None:
        created = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "akida-box.local:8002",
                "credentialRef": "launcher-secret",
            }
        )

        self.assertEqual(created["displayName"], "Lab Akida")
        self.assertEqual(created["host"], "akida-box.local")
        self.assertEqual(created["port"], 8002)
        self.assertEqual(created["baseUrl"], "http://akida-box.local:8002")
        self.assertEqual(created["state"], "unpaired")
        self.assertEqual(self.state.get_akida_host(created["id"])["id"], created["id"])
        self.assertEqual(len(self.state.list_akida_hosts()), 1)

        persisted = json.loads(
            (
                self.repo_root
                / "nmtk"
                / "neuro_toolkit"
                / "launcher_settings.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(len(persisted["akidaHosts"]), 1)
        self.assertEqual(persisted["akidaHosts"][0]["baseUrl"], "http://akida-box.local:8002")
        self.assertEqual(
            persisted["akidaHosts"][0]["credentialRef"],
            "launcher-secret",
        )

    def test_akida_host_update_rewrites_host_from_base_url(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        updated = self.state.update_akida_host(
            host["id"],
            {
                "baseUrl": "https://gpu-node.internal:9443",
            },
        )

        self.assertEqual(updated["host"], "gpu-node.internal")
        self.assertEqual(updated["port"], 9443)
        self.assertEqual(updated["baseUrl"], "https://gpu-node.internal:9443")

    def test_akida_host_update_keeps_stored_password_when_omitted(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "password",
                "password": "secret",
            }
        )

        updated = self.state.update_akida_host(
            host["id"],
            {
                "username": "operator-updated",
            },
        )

        self.assertEqual(updated["username"], "operator-updated")
        self.assertTrue(updated["hasPassword"])
        self.assertEqual(
            self.state._get_akida_host(host["id"])["password"],
            "secret",
        )

    def test_akida_host_update_keeps_password_when_blank_and_coerces_ssh_auth(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "none",
                "password": "secret",
            }
        )

        updated = self.state.update_akida_host(
            host["id"],
            {
                "username": "operator",
                "password": "",
            },
        )

        self.assertEqual(updated["authMode"], "password")
        self.assertTrue(updated["hasPassword"])
        stored = self.state._get_akida_host(host["id"])
        self.assertEqual(stored["password"], "secret")
        self.assertEqual(stored["authMode"], "password")

    def test_delete_akida_host_removes_entry_from_settings_file(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        self.state.delete_akida_host(host["id"])

        persisted = json.loads(
            (
                self.repo_root
                / "nmtk"
                / "neuro_toolkit"
                / "launcher_settings.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(persisted["akidaHosts"], [])

    def test_pynq_board_round_trip_updates_settings_file(self) -> None:
        created = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "sshPort": 22,
                "username": "xilinx",
                "authMode": "password",
                "password": "secret",
            }
        )

        self.assertEqual(created["displayName"], "Desk PYNQ")
        self.assertEqual(created["state"], "unpaired")
        self.assertTrue(created["hasPassword"])
        self.assertEqual(
            created["remoteInstallRoot"],
            "/home/xilinx/.local/share/neurochip-pynq-agent",
        )

        persisted = json.loads(
            (
                self.repo_root
                / "nmtk"
                / "neuro_toolkit"
                / "launcher_settings.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(len(persisted["pynqBoards"]), 1)
        self.assertEqual(persisted["pynqBoards"][0]["host"], "192.168.1.50")
        self.assertEqual(persisted["pynqBoards"][0]["password"], "secret")
        self.assertEqual(
            persisted["pynqBoards"][0]["remoteInstallRoot"],
            "/home/xilinx/.local/share/neurochip-pynq-agent",
        )

    def test_pynq_board_defaults_can_come_from_neurochip_manifest_contract(self) -> None:
        manifest_path = self.repo_root / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest.append(
            {
                "id": "Neurochip",
                "name": "NeuroChip",
                "description": "Hardware runtime",
                "installPath": "Neurochip",
                "launcherRuntime": {
                    "pynq": {
                        "runtimePort": 9102,
                        "sshPort": 2222,
                        "defaultUsername": "operator",
                        "defaultState": "reachable",
                        "defaultAuthMode": "ssh_key",
                        "legacyInstallRoot": "/opt/legacy-agent",
                        "installRootTemplate": "/srv/pynq/{username}",
                        "agentVenvDirName": "agent-env",
                        "runtimeVenvDirName": "runtime-env",
                        "overlayDirName": "bitfiles",
                        "serviceName": "custom-pynq-service",
                        "agentExecutableName": "custom-pynq-agent",
                        "installStatusFilename": "status.json",
                        "runtimeLogFilename": "agent.log",
                    }
                },
            }
        )
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        self.state.shutdown()
        self.state = launcher_server.LauncherControlState(
            remote_version_resolver=self._resolve_remote_version
        )

        created = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
            }
        )

        self.assertEqual(created["sshPort"], 2222)
        self.assertEqual(created["username"], "operator")
        self.assertEqual(created["authMode"], "ssh_key")
        self.assertEqual(created["state"], "reachable")
        self.assertEqual(created["runtimeApiUrl"], "http://192.168.1.50:9102")
        self.assertEqual(created["remoteInstallRoot"], "/srv/pynq/operator")
        self.assertEqual(created["remoteVenvPath"], "/srv/pynq/operator/agent-env")
        self.assertEqual(created["remotePynqVenvPath"], "/srv/pynq/operator/runtime-env")
        self.assertEqual(created["remoteOverlayDir"], "/srv/pynq/operator/bitfiles")
        self.assertEqual(created["remoteInstallStatusPath"], "/srv/pynq/operator/status.json")
        self.assertEqual(created["remoteRuntimeLogPath"], "/srv/pynq/operator/agent.log")
        self.assertEqual(created["remoteServiceName"], "custom-pynq-service")
        self.assertEqual(created["agentExecutableName"], "custom-pynq-agent")

    def test_akida_host_round_trip_updates_settings_file(self) -> None:
        created = self.state.create_akida_host(
            {
                "displayName": "Linux Akida Host",
                "runtimeApiUrl": "http://192.168.1.60:8002",
                "authMode": "bearer_token",
                "credentialRef": "akida-token",
                "hostOs": "linux",
                "pythonVersion": "3.11.8",
                "runtimeMode": "remote_sdk",
                "state": "ready",
                "lastReadinessMessage": "Remote SDK ready",
                "capabilitySnapshot": {
                    "hostSupported": True,
                    "pythonSupported": True,
                    "tensorflowAvailable": True,
                    "cnn2snnAvailable": True,
                    "akidaModelsAvailable": True,
                    "recommendedRuntime": "remote_sdk",
                },
            }
        )

        self.assertEqual(created["displayName"], "Linux Akida Host")
        self.assertEqual(created["state"], "ready")
        self.assertEqual(created["runtimeMode"], "remote_sdk")
        self.assertEqual(created["capabilitySnapshot"]["recommendedRuntime"], "remote_sdk")

        persisted = json.loads(
            (
                self.repo_root
                / "nmtk"
                / "neuro_toolkit"
                / "launcher_settings.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(len(persisted["akidaHosts"]), 1)
        self.assertEqual(
            persisted["akidaHosts"][0]["runtimeApiUrl"],
            "http://192.168.1.60:8002",
        )
        self.assertEqual(persisted["selectedAkidaHostId"], created["id"])

        reloaded = launcher_server.LauncherControlState()
        self.addCleanup(reloaded.shutdown)

        settings = reloaded.get_settings()
        self.assertEqual(settings["selectedAkidaHostId"], created["id"])
        self.assertEqual(settings["akidaHosts"][0]["hostOs"], "linux")
        self.assertEqual(settings["akidaHosts"][0]["pythonVersion"], "3.11.8")

    def test_akida_host_defaults_can_come_from_neurochip_manifest_contract(self) -> None:
        manifest_path = self.repo_root / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest.append(
            {
                "id": "Neurochip",
                "name": "NeuroChip",
                "description": "Hardware runtime",
                "installPath": "Neurochip",
                "launcherRuntime": {
                    "akida": {
                        "runtimePort": 9102,
                        "controlPort": 9190,
                        "sshPort": 2200,
                        "defaultState": "pending",
                        "defaultAuthMode": "ssh_key",
                        "installRoot": "/srv/akida-host",
                        "serviceUser": "runtime-user",
                        "venvDirName": "akida-venv",
                        "runtimeServiceName": "akida-runtime",
                        "controlServiceName": "akida-control",
                        "tokenRelativePath": "secrets/token.txt",
                        "installStatusRelativePath": "state/install.json",
                    }
                },
            }
        )
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        self.state.shutdown()
        self.state = launcher_server.LauncherControlState(
            remote_version_resolver=self._resolve_remote_version
        )

        created = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
            }
        )

        self.assertEqual(created["port"], 9102)
        self.assertEqual(created["controlPort"], 9190)
        self.assertEqual(created["sshPort"], 2200)
        self.assertEqual(created["authMode"], "ssh_key")
        self.assertEqual(created["state"], "pending")
        self.assertEqual(created["baseUrl"], "http://akida-box.local:9102")
        self.assertEqual(created["runtimeApiUrl"], "http://akida-box.local:9102")
        self.assertEqual(created["controlApiUrl"], "http://akida-box.local:9190")
        self.assertEqual(created["remoteInstallRoot"], "/srv/akida-host")
        self.assertEqual(created["remoteVenvPath"], "/srv/akida-host/akida-venv")
        self.assertEqual(created["serviceUser"], "runtime-user")
        self.assertEqual(created["runtimeServiceName"], "akida-runtime")
        self.assertEqual(created["controlServiceName"], "akida-control")
        self.assertEqual(created["tokenPath"], "/srv/akida-host/secrets/token.txt")
        self.assertEqual(created["installStatusPath"], "/srv/akida-host/state/install.json")

    def test_akida_host_update_delete_and_selection_round_trip(self) -> None:
        primary = self.state.create_akida_host(
            {
                "displayName": "Primary Host",
                "runtimeApiUrl": "http://192.168.1.60:8002",
            }
        )
        secondary = self.state.create_akida_host(
            {
                "displayName": "Secondary Host",
                "runtimeApiUrl": "http://192.168.1.61:8002",
                "state": "pending",
            }
        )

        settings = self.state.update_settings(
            {"selectedAkidaHostId": secondary["id"]}
        )
        self.assertEqual(settings["selectedAkidaHostId"], secondary["id"])

        updated = self.state.update_akida_host(
            secondary["id"],
            {
                "state": "simulator_only",
                "runtimeMode": "simulator_only",
                "hostOs": "macos",
                "pythonVersion": "3.12.1",
            },
        )
        self.assertEqual(updated["state"], "simulator_only")
        self.assertEqual(updated["runtimeMode"], "simulator_only")
        self.assertEqual(updated["hostOs"], "macos")
        self.assertEqual(updated["pythonVersion"], "3.12.1")

        self.state.delete_akida_host(secondary["id"])
        remaining = self.state.get_settings()
        self.assertEqual(len(remaining["akidaHosts"]), 1)
        self.assertEqual(remaining["akidaHosts"][0]["id"], primary["id"])
        self.assertEqual(remaining["selectedAkidaHostId"], primary["id"])

    def test_pynq_board_normalization_migrates_legacy_opt_paths(self) -> None:
        created = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
                "remoteInstallRoot": "/opt/neurochip-pynq-agent",
                "remoteVenvPath": "/opt/neurochip-pynq-agent/venv",
                "remoteOverlayDir": "/opt/neurochip-pynq-agent/overlays",
            }
        )

        self.assertEqual(
            created["remoteInstallRoot"],
            "/home/xilinx/.local/share/neurochip-pynq-agent",
        )
        self.assertEqual(
            created["remoteVenvPath"],
            "/home/xilinx/.local/share/neurochip-pynq-agent/venv",
        )
        self.assertEqual(
            created["remotePynqVenvPath"],
            "/home/xilinx/.local/share/neurochip-pynq-agent/pynq-venv",
        )
        self.assertEqual(
            created["remoteOverlayDir"],
            "/home/xilinx/.local/share/neurochip-pynq-agent/overlays",
        )

    def test_pynq_board_normalization_clears_legacy_runtime_url_when_it_matches_default(
        self,
    ) -> None:
        created = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "runtimeApiUrl": "http://192.168.1.50:8002",
            }
        )

        self.assertEqual(created["runtimeApiUrl"], "http://192.168.1.50:8002")
        self.assertEqual(created["runtimeApiUrlOverride"], "")

    def test_pynq_board_normalization_preserves_custom_legacy_runtime_url_as_override(
        self,
    ) -> None:
        created = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "runtimeApiUrl": "http://192.168.1.99:8002",
            }
        )

        self.assertEqual(created["runtimeApiUrl"], "http://192.168.1.99:8002")
        self.assertEqual(
            created["runtimeApiUrlOverride"],
            "http://192.168.1.99:8002",
        )

    def test_pynq_board_host_update_recomputes_effective_runtime_url_without_override(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.2.50",
            }
        )

        updated = self.state.update_pynq_board(
            board["id"],
            {
                "host": "192.168.2.53",
            },
        )

        self.assertEqual(updated["runtimeApiUrl"], "http://192.168.2.53:8002")
        self.assertEqual(updated["runtimeApiUrlOverride"], "")

    def test_pynq_board_update_clearing_override_resets_effective_runtime_url(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.2.50",
                "runtimeApiUrlOverride": "http://192.168.2.99:8002",
            }
        )

        updated = self.state.update_pynq_board(
            board["id"],
            {
                "host": "192.168.2.53",
                "runtimeApiUrlOverride": "",
            },
        )

        self.assertEqual(updated["runtimeApiUrl"], "http://192.168.2.53:8002")
        self.assertEqual(updated["runtimeApiUrlOverride"], "")

    def test_pynq_board_connectivity_updates_board_state(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "sshPort": 22,
                "username": "xilinx",
                "authMode": "ssh_key",
                "sshKeyPath": "/Users/test/.ssh/pynq",
            }
        )

        with mock.patch.object(self.state, "_run_ssh") as run_ssh:
            updated = self.state.test_pynq_board_connection(board["id"])

        run_ssh.assert_called_once()
        self.assertEqual(updated["state"], "reachable")

    def test_run_ssh_password_auth_uses_askpass_without_sshpass(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "sshPort": 22,
                "username": "xilinx",
                "authMode": "password",
                "password": "secret",
            }
        )
        with mock.patch.object(launcher_server.shutil, "which", return_value=None):
            command, env, cleanup = self.state._prepare_ssh_invocation(
                self.state._get_pynq_board(board["id"]),
            )

        self.assertNotIn("sshpass", command)
        self.assertIsNotNone(env)
        assert env is not None
        self.assertEqual(env["NMTK_PYNQ_PASSWORD"], "secret")
        self.assertIn("SSH_ASKPASS", env)
        askpass_path = Path(env["SSH_ASKPASS"])
        self.assertTrue(askpass_path.exists())
        self.assertIsNotNone(cleanup)
        assert cleanup is not None
        cleanup()
        self.assertFalse(askpass_path.exists())

    def test_run_ssh_ignores_benign_known_host_warning_as_primary_failure_reason(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "sshPort": 22,
                "username": "xilinx",
                "authMode": "ssh_key",
                "sshKeyPath": "/Users/test/.ssh/pynq",
            }
        )

        class _FakeStream:
            def __init__(self, lines: list[str]) -> None:
                self._lines = [f"{line}\n" for line in lines]
                self._index = 0

            def readline(self) -> str:
                if self._index >= len(self._lines):
                    return ""
                line = self._lines[self._index]
                self._index += 1
                return line

            def close(self) -> None:
                return None

        class _FakeProcess:
            def __init__(self) -> None:
                self.stdout = _FakeStream(["install script failed on remote host"])
                self.stderr = _FakeStream(
                    [
                        "Warning: Permanently added '192.168.1.50' (ED25519) to the list of known hosts."
                    ]
                )

            def wait(self) -> int:
                return 255

        with mock.patch.object(
            launcher_server.subprocess,
            "Popen",
            return_value=_FakeProcess(),
        ):
            with self.assertRaisesRegex(RuntimeError, "install script failed on remote host"):
                self.state._run_ssh(
                    self.state._get_pynq_board(board["id"]),
                    "bash /tmp/install.sh",
                )

    def test_run_scp_password_auth_uses_askpass_without_sshpass(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "sshPort": 22,
                "username": "xilinx",
                "authMode": "password",
                "password": "secret",
            }
        )
        local_file = self.repo_root / "bundle.txt"
        local_file.write_text("bundle", encoding="utf-8")
        with (
            mock.patch.object(launcher_server.shutil, "which", return_value=None),
            mock.patch.object(
                launcher_server.subprocess,
                "run",
                return_value=subprocess.CompletedProcess(["scp"], 0, "", ""),
            ) as run_mock,
        ):
            self.state._run_scp(
                self.state._get_pynq_board(board["id"]),
                local_file,
                "/tmp/bundle.txt",
            )
            run_mock.assert_called_once()
            _, kwargs = run_mock.call_args
            self.assertIn("NMTK_PYNQ_PASSWORD", kwargs.get("env", {}))

    def test_run_ssh_detached_ignores_benign_known_host_warning(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
                "authMode": "ssh_key",
                "sshKeyPath": "/Users/test/.ssh/pynq",
            }
        )

        with mock.patch.object(
            launcher_server.subprocess,
            "run",
            return_value=subprocess.CompletedProcess(
                ["ssh"],
                255,
                "",
                "Warning: Permanently added '192.168.1.50' (ED25519) to the list of known hosts.\n",
            ),
        ):
            self.state._run_ssh_detached(
                self.state._get_pynq_board(board["id"]),
                "true",
            )

    def test_restart_user_space_agent_uses_shared_neurochip_launch_command(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        install_status = {
            "agentVenvPath": "/home/xilinx/.local/share/neurochip-pynq-agent/venv",
            "pynqVenvPath": "/home/xilinx/.local/share/neurochip-pynq-agent/pynq-venv",
            "runtimeLogPath": "/home/xilinx/.local/share/neurochip-pynq-agent/runtime.log",
        }

        with (
            mock.patch.object(self.state, "_run_ssh_detached") as run_ssh_detached,
            mock.patch.object(self.state, "_wait_for_board_agent_health"),
        ):
            self.state._restart_user_space_agent(
                self.state._get_pynq_board(board["id"]),
                install_status,
            )

        remote_command = run_ssh_detached.call_args.args[1]
        self.assertIn("command -v setsid >/dev/null 2>&1", remote_command)
        self.assertIn("setsid sh -c", remote_command)
        self.assertIn("nohup sh -c", remote_command)
        self.assertNotIn("nohup env", remote_command)

    def test_akida_host_connectivity_marks_host_reachable(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={"status": "ok"},
        ) as request:
            updated = self.state.test_akida_host_connection(host["id"])

        self.assertEqual(updated["state"], "reachable")
        self.assertEqual(updated["lastPreflightMessage"], "Health reachable: ok")
        request.assert_called_once()

    def test_akida_host_preflight_reports_degraded_optional_capability(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={
                "sdk_available": False,
                "sdk_status": "sdk_unavailable",
                "sdk_issues": ["sdk_not_available", "unsupported_os"],
                "sdk_issue_detail": "BrainChip SDK missing on remote host",
                "runtime_target": "local_sdk",
                "environment_checks": {
                    "host_supported": False,
                    "python_supported": True,
                    "tensorflow_available": False,
                    "cnn2snn_available": False,
                    "akida_models_available": False,
                    "recommended_runtime": "local_sdk",
                },
            },
        ):
            result = self.state.fetch_akida_host_preflight(host["id"])

        self.assertEqual(
            result["host"]["state"],
            "degraded_optional_capability",
        )
        self.assertEqual(
            result["preflight"]["preflight_status"],
            launcher_server.PREFLIGHT_DEGRADED,
        )
        self.assertEqual(
            result["preflight"]["preflight_message"],
            "BrainChip SDK missing on remote host",
        )
        self.assertEqual(result["host"]["lastSdkStatus"], "sdk_unavailable")

    def test_akida_host_preflight_reports_failed_when_runtime_request_errors(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            side_effect=RuntimeError("remote verify exploded"),
        ):
            result = self.state.fetch_akida_host_preflight(host["id"])

        self.assertEqual(result["host"]["state"], "preflight_failed")
        self.assertEqual(
            result["preflight"]["preflight_status"],
            launcher_server.PREFLIGHT_FAILED,
        )
        self.assertIn("remote verify exploded", result["preflight"]["preflight_message"])

    def test_akida_remote_control_doctor_accepts_visible_hardware_before_model_mapping(
        self,
    ) -> None:
        namespace: dict[str, Any] = {}
        exec(provisioning_helpers._remote_control_script_text(), namespace)

        def fake_local_json(path: str) -> tuple[int, dict[str, Any]]:
            if path == "/health":
                return 200, {"status": "healthy"}
            if path == "/api/neurochip/akida/status":
                return 200, {
                    "sdk_available": True,
                    "sdk_status": "unknown",
                    "sdk_issues": [],
                    "sdk_issue_detail": None,
                    "runtime_target": "hardware",
                    "device_info": "<akida.core.HardwareDevice object>",
                    "environment_checks": {
                        "host_supported": True,
                        "python_supported": True,
                        "tensorflow_available": True,
                        "cnn2snn_available": True,
                        "akida_models_available": True,
                        "recommended_runtime": "local_sdk",
                    },
                }
            raise AssertionError(f"unexpected path: {path}")

        namespace["_local_json"] = fake_local_json
        namespace["_run_probe"] = lambda _command: ""
        namespace["_load_install_status"] = lambda: {"installMode": "systemd"}

        payload = namespace["_doctor_payload"]()

        self.assertEqual(payload["preflight"]["preflight_status"], launcher_server.PREFLIGHT_OK)
        self.assertEqual(
            payload["preflight"]["preflight_message"],
            "Akida hardware runtime is ready.",
        )
        self.assertTrue(payload["preflight"]["physicalHardwareReady"])

    def test_akida_install_script_force_reinstalls_bundled_neurochip_wheel(
        self,
    ) -> None:
        script = provisioning_helpers._akida_install_script_text(
            install_root="/opt/neurochip-akida-host",
            service_user="neurochip",
            venv_path="/opt/neurochip-akida-host/venv",
            runtime_service_name="neurochip",
            control_service_name="neurochip-akida-control",
            runtime_port=8002,
            control_port=8090,
            token_path="/opt/neurochip-akida-host/credentials/api-token",
            install_status_path="/opt/neurochip-akida-host/install-status.json",
            wheel_name="neurochip-0.6.0-py3-none-any.whl",
            required_packages=[],
        )

        self.assertIn("pip\" install --force-reinstall --no-deps", script)

    def test_akida_preflight_promotes_stale_remote_doctor_when_hardware_is_ready(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
            }
        )
        runtime_status = {
            "sdk_available": True,
            "sdk_status": "unknown",
            "sdk_issues": [],
            "runtime_target": "hardware",
        }

        updated = self.state._apply_preflight_to_akida_host(
            host["id"],
            {
                "preflight_status": launcher_server.PREFLIGHT_DEGRADED,
                "preflight_message": "Optional Akida capability is degraded.",
                "runtime_target": "hardware",
                "sdk_status": "unknown",
            },
            runtime_status=runtime_status,
            install_status={"installMode": "systemd"},
        )

        self.assertEqual(updated["state"], "ready")
        self.assertEqual(updated["lastPreflightStatus"], launcher_server.PREFLIGHT_OK)
        self.assertEqual(updated["lastPreflightMessage"], "Akida hardware runtime is ready.")

    def test_akida_host_preflight_fallback_logs_single_high_level_message(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
                "controlApiUrl": "http://akida-box.local:8090",
            }
        )

        stderr = io.StringIO()
        fallback_calls: list[tuple[str, str]] = []

        def _record_runtime_status(_host: dict[str, Any], method: str, path: str) -> dict[str, Any]:
            fallback_calls.append((method, path))
            return {
                "sdk_available": False,
                "sdk_status": "sdk_unavailable",
                "sdk_issues": ["sdk_not_available"],
                "sdk_issue_detail": "BrainChip SDK missing on remote host",
                "runtime_target": "local_sdk",
                "environment_checks": {
                    "host_supported": False,
                    "python_supported": True,
                    "tensorflow_available": False,
                    "cnn2snn_available": False,
                    "akida_models_available": False,
                    "recommended_runtime": "local_sdk",
                },
            }

        with (
            mock.patch.object(
                self.state,
                "_akida_control_json_request",
                side_effect=RuntimeError("Control request failed for GET http://akida-box.local:8090/api/remote-akida/doctor: offline"),
            ),
            mock.patch.object(
                self.state,
                "_akida_json_request",
                side_effect=_record_runtime_status,
            ),
            mock.patch.object(sys, "stderr", stderr),
        ):
            self.state.fetch_akida_host_preflight(host["id"])

        log_output = stderr.getvalue()
        self.assertEqual(fallback_calls, [("GET", "/api/neurochip/akida/status")])
        self.assertIn("remote control API unavailable during preflight", log_output)
        self.assertIn("falling back to runtime status", log_output)
        self.assertNotIn("control request failed:", log_output)

    def test_akida_host_status_fallback_logs_single_high_level_message(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
                "controlApiUrl": "http://akida-box.local:8090",
                "lastPreflightStatus": launcher_server.PREFLIGHT_OK,
            }
        )

        stderr = io.StringIO()
        with (
            mock.patch.object(
                self.state,
                "_akida_control_json_request",
                side_effect=RuntimeError(
                    "Control request failed for GET http://akida-box.local:8090/api/remote-akida/doctor: offline"
                ),
            ),
            mock.patch.object(
                self.state,
                "_akida_json_request",
                return_value={"state": "mapped", "device_info": "AKD1000"},
            ),
            mock.patch.object(sys, "stderr", stderr),
        ):
            result = self.state.fetch_akida_host_status(host["id"])

        self.assertEqual(result["host"]["state"], "ready")
        log_output = stderr.getvalue()
        self.assertIn("remote control API unavailable during status poll", log_output)
        self.assertNotIn("control request failed:", log_output)

    def test_akida_host_status_marks_mapped_host_ready(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
                "lastPreflightStatus": launcher_server.PREFLIGHT_OK,
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={"state": "mapped", "device_info": "AKD1000"},
        ):
            result = self.state.fetch_akida_host_status(host["id"])

        self.assertEqual(result["host"]["state"], "ready")
        self.assertEqual(result["status"]["state"], "mapped")

    def test_akida_host_status_marks_failed_host_error(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={"state": "failed"},
        ):
            result = self.state.fetch_akida_host_status(host["id"])

        self.assertEqual(result["host"]["state"], "error")
        self.assertEqual(result["status"]["state"], "failed")

    def test_doctor_report_includes_akida_hosts(self) -> None:
        self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
                "state": "degraded_optional_capability",
                "lastPreflightStatus": launcher_server.PREFLIGHT_DEGRADED,
                "lastPreflightMessage": "BrainChip SDK missing on remote host",
            }
        )

        with mock.patch.object(
            self.state,
            "_preflight_module",
            return_value=launcher_server.PreflightResult(
                status=launcher_server.PREFLIGHT_OK,
                message="ok",
                environment_fingerprint="fingerprint-4",
            ),
        ):
            report = self.state.doctor_report()

        self.assertIn("akidaHosts", report)
        self.assertEqual(
            report["akidaHosts"][0]["state"],
            "degraded_optional_capability",
        )
        self.assertGreaterEqual(report["degradedCount"], 1)

    def test_doctor_report_includes_pynq_boards(self) -> None:
        self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "state": "ready",
                "lastPreflightStatus": "ok",
            }
        )

        with mock.patch.object(
            self.state,
            "_preflight_module",
            return_value=launcher_server.PreflightResult(
                status=launcher_server.PREFLIGHT_OK,
                message="ok",
                environment_fingerprint="fingerprint-3",
            ),
        ):
            report = self.state.doctor_report()

        self.assertIn("pynqBoards", report)
        self.assertEqual(report["pynqBoards"][0]["state"], "ready")

    def test_doctor_report_includes_akida_hosts(self) -> None:
        self.state.create_akida_host(
            {
                "displayName": "Linux Akida Host",
                "runtimeApiUrl": "http://192.168.1.60:8002",
                "runtimeMode": "remote_sdk",
                "state": "ready",
            }
        )

        with mock.patch.object(
            self.state,
            "_preflight_module",
            return_value=launcher_server.PreflightResult(
                status=launcher_server.PREFLIGHT_OK,
                message="ok",
                environment_fingerprint="fingerprint-3",
            ),
        ):
            report = self.state.doctor_report()

        self.assertIn("akidaHosts", report)
        self.assertEqual(report["akidaHosts"][0]["runtimeMode"], "remote_sdk")
        self.assertEqual(report["akidaHosts"][0]["state"], "ready")

    def test_read_remote_pynq_install_status_decodes_machine_readable_result(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with mock.patch.object(
            self.state,
            "_run_ssh",
            return_value=json.dumps({"installMode": "user-space", "message": "fallback"}),
        ):
            status = self.state._read_remote_pynq_install_status(self.state._get_pynq_board(board["id"]))

        self.assertEqual(status["installMode"], "user-space")

    def test_restart_pynq_runtime_returns_warning_for_user_space_install(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with mock.patch.object(
            self.state,
            "_read_remote_pynq_install_status",
            return_value={"installMode": "user-space"},
        ):
            result = self.state.restart_pynq_runtime(board["id"])

        self.assertEqual(result["board"]["state"], "degraded_optional_capability")
        self.assertIn("user space", result["warning"])
        self.assertIn("Enable passwordless sudo for 'xilinx'", result["warning"])
        self.assertIn("re-run Provision Runtime", result["warning"])

    def test_restart_pynq_runtime_waits_for_health_before_preflight_when_systemd_managed(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        events: list[str] = []

        def record_run_ssh(*_args: Any, **_kwargs: Any) -> str:
            events.append("ssh")
            return ""

        def record_wait(*_args: Any, **_kwargs: Any) -> None:
            events.append("wait")

        def record_preflight(*_args: Any, **_kwargs: Any) -> dict[str, Any]:
            events.append("preflight")
            return {"board": {"state": "ready"}}

        with (
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(self.state, "_run_ssh", side_effect=record_run_ssh),
            mock.patch.object(
                self.state,
                "_wait_for_board_agent_health",
                side_effect=record_wait,
            ) as wait_for_health,
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                side_effect=record_preflight,
            ) as fetch_preflight,
        ):
            result = self.state.restart_pynq_runtime(board["id"])

        wait_for_health.assert_called_once()
        fetch_preflight.assert_called_once_with(
            board["id"],
            request_timeout=launcher_server.DEFAULT_PYNQ_PREFLIGHT_TIMEOUT_SECONDS,
        )
        self.assertEqual(events, ["ssh", "wait", "preflight"])
        self.assertEqual(result["board"]["state"], "ready")

    def test_describe_pynq_preflight_reports_overlay_missing_actionably(self) -> None:
        description = launcher_server._describe_pynq_preflight(
            {
                "preflight_status": "failed",
                "preflight_message": "Install Overlay next. Checked bitstream path: /tmp/snn_overlay.bit.",
                "overlay_assets": {"ready_for_hardware": False},
            }
        )

        self.assertIn("overlay assets missing", description)
        self.assertIn("/tmp/snn_overlay.bit", description)

    def test_describe_pynq_preflight_surfaces_runtime_probe_context(self) -> None:
        description = launcher_server._describe_pynq_preflight(
            {
                "preflight_status": "failed",
                "preflight_message": (
                    "Hardware runtime assets are present, but the board cannot open a usable "
                    "PYNQ device yet. Runtime probe failed: Bitstream not found: "
                    "snn_overlay.bit. Checked bitstream path: "
                    "/home/xilinx/.local/share/neurochip-pynq-agent/overlays/snn_overlay.bit."
                ),
                "overlay_assets": {"ready_for_hardware": True},
            }
        )

        self.assertIn("Bitstream not found", description)
        self.assertIn("/home/xilinx/.local/share/neurochip-pynq-agent/overlays/snn_overlay.bit", description)

    def test_provision_pynq_board_reports_install_status(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with (
            mock.patch.object(self.state, "_build_local_pynq_bundle"),
            mock.patch.object(self.state, "_run_ssh"),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "user-space"},
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                return_value={"board": {"state": "degraded_optional_capability"}},
            ),
        ):
            result = self.state.provision_pynq_board(board["id"])

        self.assertEqual(result["installStatus"]["installMode"], "user-space")
        self.assertEqual(result["board"]["state"], "degraded_optional_capability")
        self.assertIn(
            "Enable passwordless sudo for 'xilinx'",
            result["board"]["lastPreflightMessage"],
        )
        self.assertIn(
            "re-run Provision Runtime",
            result["board"]["lastPreflightMessage"],
        )

    def test_provision_pynq_board_tails_runtime_log_when_install_script_fails(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with (
            mock.patch.object(self.state, "_build_local_pynq_bundle"),
            mock.patch.object(
                self.state,
                "_run_ssh",
                side_effect=["", RuntimeError("install script failed on remote host")],
            ),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(self.state, "_emit_runtime_log_tail") as emit_runtime_log_tail,
        ):
            result = self.state.provision_pynq_board(board["id"])

        emit_runtime_log_tail.assert_called_once()
        self.assertEqual(emit_runtime_log_tail.call_args.args[1], {})
        self.assertEqual(result["error"], "install script failed on remote host")
        self.assertEqual(result["board"]["state"], "provision_failed")
        self.assertEqual(
            result["board"]["lastPreflightMessage"],
            "install script failed on remote host",
        )

    def test_install_pynq_overlay_assets_reports_missing_staged_package(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with (
            mock.patch.object(self.state, "_run_ssh") as run_ssh,
            mock.patch.object(self.state, "_run_scp") as run_scp,
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        self.assertEqual(result["board"]["state"], "overlay_missing")
        self.assertIn("Local staged overlay package is incomplete", result["board"]["lastPreflightMessage"])
        self.assertIn(
            str(self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"),
            result["board"]["lastPreflightMessage"],
        )
        self.assertFalse(result["localOverlayPackage"]["ready"])
        run_ssh.assert_not_called()
        run_scp.assert_not_called()

    def test_install_pynq_overlay_assets_uploads_staged_package(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        staging_dir.mkdir(parents=True, exist_ok=True)
        bitstream = staging_dir / "snn_overlay.bit"
        hwh = staging_dir / "snn_overlay.hwh"
        manifest = staging_dir / "overlay_manifest.json"
        bitstream.write_bytes(b"bitstream")
        hwh.write_text("<hwh/>", encoding="utf-8")
        manifest.write_text(
            json.dumps(
                {
                    "overlay_id": "snn_overlay_v1",
                    "overlay_version": "1.0.1",
                    "target_part": "xc7z020clg400-1",
                    "supported_neuron_models": ["LIF"],
                    "supported_weight_bit_widths": [8],
                    "max_neurons": 256,
                    "max_synapses": 15360,
                    "max_populations": 2,
                    "dma_ip_name": "axi_dma_0",
                    "snn_ip_name": "snn_engine_0",
                    "register_map": {
                        "base_address": 1073741824,
                        "control_reg_offset": 0,
                        "status_reg_offset": 4,
                        "population_count_offset": 8,
                        "input_neuron_count_offset": 12,
                        "output_neuron_count_offset": 16,
                        "timestep_count_offset": 20,
                        "threshold_base_offset": 256,
                        "neuron_base_offset": 256,
                        "weight_base_offset": 4096,
                        "dma_channel": "axi_dma_0",
                        "input_buffer_addr": 0,
                        "output_buffer_addr": 0,
                        "timestep_us": 1000,
                    },
                    "weight_layout": {
                        "format": "int8_dense_row_major_word_mmio",
                        "storage": "mmio",
                        "base_offset": 4096,
                        "stride_bytes": 4,
                        "max_entries": 15360,
                    },
                    "threshold_layout": {
                        "format": "float32_per_population",
                        "storage": "mmio",
                        "base_offset": 256,
                        "stride_bytes": 4,
                        "max_entries": 2,
                    },
                },
                indent=2,
            ),
            encoding="utf-8",
        )

        with (
            mock.patch.object(self.state, "_run_ssh") as run_ssh,
            mock.patch.object(self.state, "_run_scp") as run_scp,
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(self.state, "_restart_user_space_agent") as restart_agent,
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                return_value={"board": {"state": "ready"}},
            ),
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        run_ssh.assert_called_once_with(
            self.state._get_pynq_board(board["id"]),
            f"mkdir -p {board['remoteOverlayDir']}",
        )
        restart_agent.assert_not_called()
        self.assertEqual(run_scp.call_count, 3)
        self.assertEqual(run_scp.call_args_list[0].args[1].resolve(), bitstream.resolve())
        self.assertEqual(
            run_scp.call_args_list[0].args[2],
            f"{board['remoteOverlayDir']}/snn_overlay.bit",
        )
        self.assertEqual(run_scp.call_args_list[1].args[1].resolve(), hwh.resolve())
        self.assertEqual(
            run_scp.call_args_list[1].args[2],
            f"{board['remoteOverlayDir']}/snn_overlay.hwh",
        )
        self.assertEqual(run_scp.call_args_list[2].args[1].resolve(), manifest.resolve())
        self.assertEqual(
            run_scp.call_args_list[2].args[2],
            f"{board['remoteOverlayDir']}/overlay_manifest.json",
        )
        self.assertTrue(result["localOverlayPackage"]["ready"])
        self.assertNotIn("overlayRestartWarning", result)

    def test_install_pynq_overlay_assets_restarts_user_space_agent(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(staging_dir)

        with (
            mock.patch.object(self.state, "_run_ssh"),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "user-space"},
            ),
            mock.patch.object(self.state, "_restart_user_space_agent") as restart_agent,
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                return_value={"board": {"state": "degraded_optional_capability"}},
            ),
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        restart_agent.assert_called_once()
        self.assertNotIn("overlayRestartWarning", result)

    def test_install_pynq_overlay_assets_returns_warning_when_agent_restart_times_out(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(staging_dir)

        emissions: list[tuple[str, bool]] = []

        def record_emit(_board: Any, message: str, *, stderr: bool = False) -> None:
            emissions.append((message, stderr))

        with (
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_run_ssh",
                side_effect=[None, "line1\nline2\n"],
            ),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={
                    "installMode": "user-space",
                    "runtimeLogPath": "/home/xilinx/.local/share/neurochip-pynq-agent/runtime.log",
                },
            ),
            mock.patch.object(
                self.state,
                "_restart_user_space_agent",
                side_effect=RuntimeError("agent did not become healthy within 60s"),
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                return_value={"board": {"state": "degraded_optional_capability"}},
            ),
            mock.patch.object(self.state, "_emit_pynq_terminal_log", side_effect=record_emit),
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        self.assertIn("overlayRestartWarning", result)
        self.assertIn("agent did not become healthy", result["overlayRestartWarning"])
        tail_messages = [msg for msg, _stderr in emissions if msg.startswith("runtime.log | ")]
        self.assertEqual(
            tail_messages,
            ["runtime.log | line1", "runtime.log | line2"],
        )
        summary_messages = [
            msg for msg, _stderr in emissions if "restart did not become healthy" in msg
        ]
        self.assertTrue(summary_messages, "expected a summary line about restart failure")

    def test_install_pynq_overlay_assets_degrades_when_readiness_refresh_fails_after_upload(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(staging_dir)

        emissions: list[tuple[str, bool]] = []

        def record_emit(_board: Any, message: str, *, stderr: bool = False) -> None:
            emissions.append((message, stderr))

        with (
            mock.patch.object(self.state, "_run_ssh"),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "user-space"},
            ),
            mock.patch.object(
                self.state,
                "_restart_user_space_agent",
                side_effect=RuntimeError("agent did not become healthy within 60s"),
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                side_effect=RuntimeError("connection refused"),
            ),
            mock.patch.object(self.state, "_emit_pynq_terminal_log", side_effect=record_emit),
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        self.assertEqual(result["board"]["state"], "degraded_optional_capability")
        self.assertEqual(result["board"]["lastPreflightStatus"], "degraded")
        self.assertEqual(
            result["board"]["lastPreflightMessage"],
            launcher_server.PYNQ_OVERLAY_UPLOAD_RECOVERY_MESSAGE,
        )
        self.assertIn("overlayRestartWarning", result)
        self.assertIn("agent did not become healthy", result["overlayRestartWarning"])
        duplicate_refresh_messages = [
            msg for msg, _stderr in emissions if "readiness refresh after overlay upload did not complete" in msg
        ]
        self.assertEqual(
            duplicate_refresh_messages,
            [],
            "restart failure should remain the single summary line for this recovery path",
        )

    def test_install_pynq_overlay_assets_preserves_explicit_overlay_missing_preflight(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(staging_dir)

        with (
            mock.patch.object(self.state, "_run_ssh"),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                return_value={
                    "board": {
                        "state": "overlay_missing",
                        "lastPreflightStatus": "failed",
                        "lastPreflightMessage": "Install Overlay next.",
                    }
                },
            ),
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        self.assertEqual(result["board"]["state"], "overlay_missing")
        self.assertNotIn("overlayRestartWarning", result)

    def test_install_pynq_overlay_assets_preserves_explicit_preflight_failure(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(staging_dir)

        with (
            mock.patch.object(self.state, "_run_ssh"),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                return_value={
                    "board": {
                        "state": "preflight_failed",
                        "lastPreflightStatus": "failed",
                        "lastPreflightMessage": "Runtime probe failed: No Devices Found.",
                    }
                },
            ),
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        self.assertEqual(result["board"]["state"], "preflight_failed")
        self.assertNotIn("overlayRestartWarning", result)

    def test_inspect_local_pynq_overlay_package_validates_manifest_without_importing_neurochip(
        self,
    ) -> None:
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(staging_dir)
        manifest_path = staging_dir / "overlay_manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["weight_layout"]["stride_bytes"] = 8
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

        status = self.state._inspect_local_pynq_overlay_package()

        self.assertFalse(status["ready"])
        self.assertFalse(status["manifestValid"])
        self.assertIn(
            "weight_layout.stride_bytes must match overlay-v1 word-MMIO stride",
            "\n".join(status["issues"]),
        )

    def test_build_remote_pynq_user_space_launch_command_is_launcher_owned(
        self,
    ) -> None:
        command = self.state._build_remote_pynq_user_space_launch_command(
            agent_venv_path="/opt/agent",
            pynq_venv_path="/opt/pynq",
            install_status_path="/tmp/install-status.json",
            overlay_dir="/srv/overlay",
            runtime_log_path="/tmp/runtime.log",
            agent_executable_name="custom-agent",
        )

        self.assertIn("NEUROCHIP_PYNQ_OVERLAY_DIR=/srv/overlay", command)
        self.assertIn("/tmp/runtime.log", command)
        self.assertNotIn("Neurochip/neurochip/provisioning", command)

    def test_build_remote_pynq_user_space_launch_command_does_not_depend_on_neurochip_files(
        self,
    ) -> None:
        original_exists = Path.exists

        def fake_exists(path: Path) -> bool:
            if "Neurochip/neurochip/provisioning" in str(path):
                return False
            return original_exists(path)

        with mock.patch.object(Path, "exists", autospec=True, side_effect=fake_exists):
            command = self.state._build_remote_pynq_user_space_launch_command(
                agent_venv_path="/opt/agent",
                pynq_venv_path="/opt/pynq",
                install_status_path="/tmp/install-status.json",
                overlay_dir="/srv/overlay",
                runtime_log_path="/tmp/runtime.log",
                agent_executable_name="custom-agent",
            )

        self.assertIn("NEUROCHIP_PYNQ_OVERLAY_DIR=/srv/overlay", command)

    def test_build_local_pynq_bundle_is_launcher_owned(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
                "overlayVersion": "2026.04",
            }
        )
        bundle_dir = self.repo_root / "tmp-pynq-bundle"
        bundle_dir.mkdir(parents=True, exist_ok=True)
        wheel_path = self.repo_root / "Neurochip" / "dist" / "neurochip-test.whl"
        wheel_path.parent.mkdir(parents=True, exist_ok=True)
        wheel_path.write_text("wheel", encoding="utf-8")

        with mock.patch.object(
            provisioning_helpers,
            "ensure_agent_wheel",
            return_value=wheel_path,
        ):
            result = self.state._build_local_pynq_bundle(board, bundle_dir)

        manifest = json.loads(
            (bundle_dir / "bundle-manifest.json").read_text(encoding="utf-8")
        )
        self.assertEqual(manifest["overlay"]["overlayVersion"], "2026.04")
        self.assertEqual(result["wheelName"], "neurochip-test.whl")
        self.assertTrue((bundle_dir / "install-pynq-agent.sh").exists())

    def test_build_local_pynq_bundle_does_not_depend_on_neurochip_provisioning_tree(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
                "overlayVersion": "2026.04",
            }
        )
        bundle_dir = self.repo_root / "tmp-pynq-bundle"
        bundle_dir.mkdir(parents=True, exist_ok=True)
        wheel_path = self.repo_root / "Neurochip" / "dist" / "neurochip-test.whl"
        wheel_path.parent.mkdir(parents=True, exist_ok=True)
        wheel_path.write_text("wheel", encoding="utf-8")
        original_exists = Path.exists

        def fake_exists(path: Path) -> bool:
            if "Neurochip/neurochip/provisioning" in str(path):
                return False
            return original_exists(path)

        with (
            mock.patch.object(
                provisioning_helpers,
                "ensure_agent_wheel",
                return_value=wheel_path,
            ),
            mock.patch.object(Path, "exists", autospec=True, side_effect=fake_exists),
        ):
            result = self.state._build_local_pynq_bundle(board, bundle_dir)

        self.assertEqual(result["wheelName"], "neurochip-test.whl")

    def test_build_local_akida_bundle_is_launcher_owned(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )
        bundle_dir = self.repo_root / "tmp-akida-bundle"
        bundle_dir.mkdir(parents=True, exist_ok=True)
        wheel_path = self.repo_root / "Neurochip" / "dist" / "neurochip-test.whl"
        wheel_path.parent.mkdir(parents=True, exist_ok=True)
        wheel_path.write_text("wheel", encoding="utf-8")

        with (
            mock.patch.object(
                provisioning_helpers,
                "ensure_agent_wheel",
                return_value=wheel_path,
            ),
            mock.patch.object(
                self.state,
                "_get_module",
                return_value={
                    "akidaRuntime": {
                        "requiredPackages": [
                            "tensorflow==2.19.*",
                            "akida==2.19.1",
                            "cnn2snn==2.19.1",
                            "akida-models==1.13.1",
                        ]
                    }
                },
            ),
        ):
            result = self.state._build_local_akida_bundle(host, bundle_dir)

        self.assertEqual(
            result["requiredPackages"],
            [
                "tensorflow==2.19.*",
                "akida==2.19.1",
                "cnn2snn==2.19.1",
                "akida-models==1.13.1",
            ],
        )
        # Control port should come from the typed contract, not a raw constant.
        self.assertEqual(
            result["controlPort"],
            launcher_server.AkidaLauncherRuntimeContract().control_port,
        )
        self.assertIn(
            "tensorflow==2.19.*",
            (bundle_dir / "bundle-manifest.json").read_text(encoding="utf-8"),
        )
        install_script = (bundle_dir / "install-akida-host.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("sudo_available()", install_script)
        self.assertIn("write_sudo_file()", install_script)
        self.assertIn("NMTK_AKIDA_SUDO_PASSWORD", install_script)
        self.assertIn("sudo_cmd apt-get update", install_script)
        self.assertIn('if [ ! -s "$TOKEN_PATH" ]; then', install_script)
        self.assertIn('token_tmp="$(mktemp)"', install_script)
        self.assertIn('sudo_cmd install -D -m 0600 -o "$SERVICE_USER" -g "$SERVICE_USER" "$token_tmp" "$TOKEN_PATH"', install_script)
        self.assertIn('if [ -z "$TOKEN_VALUE" ]; then', install_script)
        self.assertIn('INSTALL_STATUS_PAYLOAD="$(sudo_cmd cat "$INSTALL_STATUS_PATH")"', install_script)
        self.assertIn('if [ -z "$INSTALL_STATUS_PAYLOAD" ]; then', install_script)
        self.assertNotIn("| sudo_cmd tee", install_script)
        self.assertNotIn("sudo -n apt-get update", install_script)
        self.assertTrue((bundle_dir / "wheels" / "neurochip-test.whl").exists())

    def test_build_local_akida_bundle_does_not_depend_on_neurochip_provisioning_tree(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )
        bundle_dir = self.repo_root / "tmp-akida-bundle"
        bundle_dir.mkdir(parents=True, exist_ok=True)
        wheel_path = self.repo_root / "Neurochip" / "dist" / "neurochip-test.whl"
        wheel_path.parent.mkdir(parents=True, exist_ok=True)
        wheel_path.write_text("wheel", encoding="utf-8")
        original_exists = Path.exists

        def fake_exists(path: Path) -> bool:
            if "Neurochip/neurochip/provisioning" in str(path):
                return False
            return original_exists(path)

        with (
            mock.patch.object(
                provisioning_helpers,
                "ensure_agent_wheel",
                return_value=wheel_path,
            ),
            mock.patch.object(
                self.state,
                "_get_module",
                return_value={
                    "akidaRuntime": {
                        "requiredPackages": [
                            "tensorflow==2.19.*",
                            "akida==2.19.1",
                            "cnn2snn==2.19.1",
                            "akida-models==1.13.1",
                        ]
                    }
                },
            ),
            mock.patch.object(Path, "exists", autospec=True, side_effect=fake_exists),
        ):
            result = self.state._build_local_akida_bundle(host, bundle_dir)

        self.assertEqual(result["requiredPackages"][0], "tensorflow==2.19.*")
        self.assertTrue((bundle_dir / "wheels" / "neurochip-test.whl").exists())

    def test_pynq_ssh_invocation_uses_contract_ssh_port_as_fallback(self) -> None:
        """SSH command uses the manifest-owned pynq.sshPort when none is stored."""
        manifest_path = (
            self.repo_root / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest.append(
            {
                "id": "Neurochip",
                "name": "NeuroChip",
                "installPath": "Neurochip",
                "launcherRuntime": {
                    "pynq": {"sshPort": 2300},
                },
            }
        )
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        # Board dict with no sshPort key — simulates absent or pre-normalization state.
        board = {"authMode": "ssh_key", "sshKeyPath": "/tmp/fake-pynq-key"}
        command, _env, _cleanup = self.state._prepare_ssh_invocation(board)

        # SSH non-copy-mode uses "-p" followed by the port argument.
        port_index = command.index("-p") + 1
        self.assertEqual(command[port_index], "2300")

    def test_akida_ssh_invocation_uses_contract_ssh_port_as_fallback(self) -> None:
        """SSH command uses the manifest-owned akida.sshPort when none is stored."""
        manifest_path = (
            self.repo_root / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest.append(
            {
                "id": "Neurochip",
                "name": "NeuroChip",
                "installPath": "Neurochip",
                "launcherRuntime": {
                    "akida": {"sshPort": 2400},
                },
            }
        )
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        host = {"authMode": "ssh_key", "sshKeyPath": "/tmp/fake-akida-key"}
        command, _env, _cleanup = self.state._prepare_akida_ssh_invocation(host)

        port_index = command.index("-p") + 1
        self.assertEqual(command[port_index], "2400")

    def test_akida_ssh_password_auth_requires_stored_password(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "192.168.1.60",
                "username": "operator",
                "authMode": "password",
            }
        )

        with self.assertRaisesRegex(
            RuntimeError,
            "No SSH password is configured for this Akida host",
        ):
            self.state._prepare_akida_ssh_invocation(self.state._get_akida_host(host["id"]))

    def test_akida_ssh_requires_supported_credential_mode(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "192.168.1.60",
                "username": "operator",
                "authMode": "none",
            }
        )

        with self.assertRaisesRegex(
            RuntimeError,
            "Akida host SSH operations require password or SSH-key authentication",
        ):
            self.state._prepare_akida_ssh_invocation(self.state._get_akida_host(host["id"]))

    def test_akida_ssh_password_auth_uses_askpass_without_sshpass(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "192.168.1.60",
                "username": "operator",
                "authMode": "password",
                "password": "secret",
            }
        )

        with mock.patch.object(launcher_server.shutil, "which", return_value=None):
            command, env, cleanup = self.state._prepare_akida_ssh_invocation(
                self.state._get_akida_host(host["id"])
            )

        self.assertNotIn("sshpass", command)
        self.assertIsNotNone(env)
        assert env is not None
        self.assertEqual(env["NMTK_AKIDA_PASSWORD"], "secret")
        self.assertIn("SSH_ASKPASS", env)
        askpass_path = Path(env["SSH_ASKPASS"])
        self.assertTrue(askpass_path.exists())
        self.assertIsNotNone(cleanup)
        assert cleanup is not None
        cleanup()
        self.assertFalse(askpass_path.exists())

    def test_build_local_akida_bundle_uses_contract_ports_as_fallback(self) -> None:
        """Bundle assembly uses manifest-owned akida runtime/control ports when absent."""
        manifest_path = (
            self.repo_root / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest.append(
            {
                "id": "Neurochip",
                "name": "NeuroChip",
                "installPath": "Neurochip",
                "launcherRuntime": {
                    "akida": {"runtimePort": 9200, "controlPort": 9290},
                },
            }
        )
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        # Host dict without port/controlPort — forces the contract fallback path.
        host = {
            "id": "test-akida",
            "remoteInstallRoot": "/opt/neurochip-akida-host",
            "serviceUser": "neurochip",
            "remoteVenvPath": "/opt/neurochip-akida-host/venv",
            "runtimeServiceName": "neurochip",
            "controlServiceName": "neurochip-akida-control",
            "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/opt/neurochip-akida-host/install-status.json",
        }
        bundle_dir = self.repo_root / "tmp-contract-akida-bundle"
        bundle_dir.mkdir(parents=True, exist_ok=True)
        wheel_path = self.repo_root / "Neurochip" / "dist" / "neurochip-contract-test.whl"
        wheel_path.parent.mkdir(parents=True, exist_ok=True)
        wheel_path.write_text("wheel", encoding="utf-8")

        with (
            mock.patch.object(
                provisioning_helpers,
                "ensure_agent_wheel",
                return_value=wheel_path,
            ),
            mock.patch.object(
                self.state,
                "_get_module",
                return_value={
                    "akidaRuntime": {
                        "requiredPackages": ["akida==2.19.1"],
                    }
                },
            ),
        ):
            result = self.state._build_local_akida_bundle(host, bundle_dir)

        self.assertEqual(result["runtimePort"], 9200)
        self.assertEqual(result["controlPort"], 9290)

    def test_apply_preflight_to_akida_host_marks_user_space_install_degraded(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
            }
        )

        updated = self.state._apply_preflight_to_akida_host(
            host["id"],
            {
                "preflight_status": launcher_server.PREFLIGHT_OK,
                "preflight_message": "Akida hardware runtime is ready.",
                "runtime_target": "hardware",
                "sdk_status": "deployable",
            },
            install_status={"installMode": "user-space"},
        )

        self.assertEqual(updated["state"], "degraded_optional_capability")
        self.assertIn("Runtime is installed in user space.", updated["lastPreflightMessage"])
        self.assertIn("Enable passwordless sudo for 'operator'", updated["lastPreflightMessage"])

    def test_restart_akida_host_services_returns_warning_for_user_space_install(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
            }
        )

        with mock.patch.object(
            self.state,
            "_read_remote_akida_install_status",
            return_value={"installMode": "user-space"},
        ):
            result = self.state.restart_akida_host_services(host["id"])

        self.assertEqual(result["host"]["state"], "degraded_optional_capability")
        self.assertIn("user space", result["warning"])
        self.assertIn("Enable passwordless sudo for 'operator'", result["warning"])
        self.assertIn("re-run Provision Runtime", result["warning"])

    def test_provision_akida_host_updates_paths_from_user_space_install_status(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/fake-akida-key",
            }
        )
        install_status = {
            "installMode": "user-space",
            "message": "Akida host installed in user space; auto-start requires privileged setup.",
            "runtimeApiUrl": "http://akida-box.local:8002",
            "controlApiUrl": "http://akida-box.local:8090",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "operator",
            "venvPath": "/home/operator/.local/share/neurochip-akida-host/venv",
            "installRoot": "/home/operator/.local/share/neurochip-akida-host",
            "tokenPath": "/home/operator/.local/share/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/home/operator/.local/share/neurochip-akida-host/install-status.json",
            "autoStartSupported": False,
        }
        install_output = (
            "[install-akida-host] done\n"
            f"INSTALL_STATUS_JSON={json.dumps(install_status, sort_keys=True)}\n"
        )

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ),
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(self.state, "_read_remote_akida_token", return_value="token-123"),
            mock.patch.object(
                self.state,
                "fetch_akida_host_preflight",
                return_value={"host": {"state": "degraded_optional_capability"}},
            ),
        ):
            result = self.state.provision_akida_host(host["id"])

        updated = self.state.get_akida_host(host["id"])
        self.assertEqual(result["installStatus"]["installMode"], "user-space")
        self.assertEqual(
            updated["remoteInstallRoot"],
            "/home/operator/.local/share/neurochip-akida-host",
        )
        self.assertEqual(updated["serviceUser"], "operator")
        self.assertEqual(
            updated["tokenPath"],
            "/home/operator/.local/share/neurochip-akida-host/credentials/api-token",
        )
        self.assertEqual(
            updated["installStatusPath"],
            "/home/operator/.local/share/neurochip-akida-host/install-status.json",
        )
        self.assertEqual(updated["credentialRef"], "token-123")
        self.assertEqual(updated["runtimeApiUrl"], "http://akida-box.local:8002")
        self.assertEqual(updated["controlApiUrl"], "http://akida-box.local:8090")

    def test_provision_akida_host_falls_back_to_remote_status_when_sentinel_blank(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/fake-akida-key",
            }
        )
        install_status = {
            "installMode": "systemd",
            "message": "Akida host installation completed.",
            "runtimeApiUrl": "http://akida-box.local:8002",
            "controlApiUrl": "http://akida-box.local:8090",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "neurochip",
            "venvPath": "/opt/neurochip-akida-host/venv",
            "installRoot": "/opt/neurochip-akida-host",
            "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/opt/neurochip-akida-host/install-status.json",
            "autoStartSupported": True,
        }
        install_output = "[install-akida-host] done\nINSTALL_STATUS_JSON=\n"

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ),
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_akida_install_status",
                return_value=install_status,
            ) as read_status,
            mock.patch.object(self.state, "_read_remote_akida_token", return_value="token-123"),
            mock.patch.object(
                self.state,
                "fetch_akida_host_preflight",
                return_value={"host": {"state": "ready"}},
            ),
        ):
            result = self.state.provision_akida_host(host["id"])

        self.assertEqual(result["installStatus"]["installMode"], "systemd")
        read_status.assert_called_once()

    def test_provision_akida_host_parses_multiline_install_status_sentinel(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/fake-akida-key",
            }
        )
        install_status = {
            "installMode": "systemd",
            "message": "Akida host installation completed.",
            "runtimeApiUrl": "http://akida-box.local:8002",
            "controlApiUrl": "http://akida-box.local:8090",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "neurochip",
            "venvPath": "/opt/neurochip-akida-host/venv",
            "installRoot": "/opt/neurochip-akida-host",
            "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/opt/neurochip-akida-host/install-status.json",
            "autoStartSupported": True,
            "state": "ready",
        }
        install_output = (
            "INSTALL_STATUS_JSON={\n"
            '  "autoStartSupported": true,\n'
            '  "controlApiUrl": "http://akida-box.local:8090",\n'
            '  "hostOs": "linux",\n'
            '  "installMode": "systemd",\n'
            '  "installRoot": "/opt/neurochip-akida-host",\n'
            '  "installStatusPath": "/opt/neurochip-akida-host/install-status.json",\n'
            '  "message": "Akida host installation completed.",\n'
            '  "pythonVersion": "3.11.8",\n'
            '  "runtimeApiUrl": "http://akida-box.local:8002",\n'
            '  "serviceUser": "neurochip",\n'
            '  "state": "ready",\n'
            '  "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",\n'
            '  "venvPath": "/opt/neurochip-akida-host/venv"\n'
            "}\n"
            "[install-akida-host] Install script completed successfully\n"
        )

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ),
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(self.state, "_read_remote_akida_token", return_value="token-123"),
            mock.patch.object(
                self.state,
                "fetch_akida_host_preflight",
                return_value={"host": {"state": "ready"}},
            ),
        ):
            result = self.state.provision_akida_host(host["id"])

        self.assertEqual(result["installStatus"], install_status)
        updated = self.state.get_akida_host(host["id"])
        self.assertEqual(updated["runtimeApiUrl"], "http://akida-box.local:8002")
        self.assertEqual(updated["controlApiUrl"], "http://akida-box.local:8090")

    def test_provision_akida_host_passes_sudo_password_without_logging_it(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "password",
                "password": "secret",
            }
        )
        install_status = {
            "installMode": "systemd",
            "message": "Akida host installation completed.",
            "runtimeApiUrl": "http://akida-box.local:8002",
            "controlApiUrl": "http://akida-box.local:8090",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "neurochip",
            "venvPath": "/opt/neurochip-akida-host/venv",
            "installRoot": "/opt/neurochip-akida-host",
            "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/opt/neurochip-akida-host/install-status.json",
            "autoStartSupported": True,
        }
        install_output = (
            "[install-akida-host] done\n"
            f"INSTALL_STATUS_JSON={json.dumps(install_status, sort_keys=True)}\n"
        )

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ) as run_ssh,
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(self.state, "_read_remote_akida_token", return_value="token-123"),
            mock.patch.object(
                self.state,
                "fetch_akida_host_preflight",
                return_value={"host": {"state": "ready"}},
            ),
        ):
            self.state.provision_akida_host(host["id"])

        install_call = run_ssh.call_args_list[1]
        remote_command = install_call.args[1]
        display_command = install_call.kwargs["display_command"]
        self.assertIn("NMTK_AKIDA_SUDO_PASSWORD=secret", remote_command)
        self.assertIn("NMTK_AKIDA_SUDO_PASSWORD=<redacted>", display_command)
        self.assertNotIn("secret", display_command)

    def test_read_remote_akida_token_uses_sudo_password_without_logging_it(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "password",
                "password": "secret",
            }
        )

        with mock.patch.object(
            self.state,
            "_run_akida_ssh",
            return_value="token-123\n",
        ) as run_ssh:
            token = self.state._read_remote_akida_token(
                self.state._get_akida_host(host["id"]),
                install_status={"installMode": "systemd"},
            )

        self.assertEqual(token, "token-123")
        remote_command = run_ssh.call_args.args[1]
        display_command = run_ssh.call_args.kwargs["display_command"]
        self.assertIn("printf '%s\\n' secret | sudo -S -p '' cat", remote_command)
        self.assertIn("sudo -S -p '' cat", remote_command)
        self.assertIn("printf '%s\\n' <redacted> | sudo -S -p '' cat", display_command)
        self.assertNotIn("NMTK_AKIDA_SUDO_PASSWORD", remote_command)
        self.assertNotIn("secret", display_command)

    def test_provision_akida_host_fails_when_remote_token_is_empty(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/fake-akida-key",
            }
        )
        install_status = {
            "installMode": "systemd",
            "message": "Akida host installation completed.",
            "runtimeApiUrl": "http://unresolvable-hostname:8002",
            "controlApiUrl": "http://unresolvable-hostname:8090",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "neurochip",
            "venvPath": "/opt/neurochip-akida-host/venv",
            "installRoot": "/opt/neurochip-akida-host",
            "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/opt/neurochip-akida-host/install-status.json",
            "autoStartSupported": True,
        }
        install_output = (
            "[install-akida-host] done\n"
            f"INSTALL_STATUS_JSON={json.dumps(install_status, sort_keys=True)}\n"
        )

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ),
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(self.state, "_read_remote_akida_token", return_value=""),
        ):
            result = self.state.provision_akida_host(host["id"])

        self.assertIn("empty value", result["error"])

    def test_resolve_pynq_agent_health_timeout_respects_env_and_bounds(self) -> None:
        cases = {
            "": launcher_server.DEFAULT_PYNQ_AGENT_HEALTH_TIMEOUT_SECONDS,
            "45": 45.0,
            "2": launcher_server.PYNQ_AGENT_HEALTH_TIMEOUT_BOUNDS[0],
            "9999": launcher_server.PYNQ_AGENT_HEALTH_TIMEOUT_BOUNDS[1],
            "not-a-number": launcher_server.DEFAULT_PYNQ_AGENT_HEALTH_TIMEOUT_SECONDS,
        }
        for raw, expected in cases.items():
            with mock.patch.dict(
                os.environ,
                {"NEUROCHIP_PYNQ_HEALTH_TIMEOUT_SECONDS": raw},
                clear=False,
            ):
                self.assertEqual(
                    launcher_server._resolve_pynq_agent_health_timeout(), expected, raw
                )

    def test_resolve_pynq_preflight_timeout_respects_env_and_bounds(self) -> None:
        cases = {
            "": launcher_server.DEFAULT_PYNQ_PREFLIGHT_TIMEOUT_SECONDS,
            "60": 60.0,
            "1": launcher_server.PYNQ_PREFLIGHT_TIMEOUT_BOUNDS[0],
            "9999": launcher_server.PYNQ_PREFLIGHT_TIMEOUT_BOUNDS[1],
            "not-a-number": launcher_server.DEFAULT_PYNQ_PREFLIGHT_TIMEOUT_SECONDS,
        }
        for raw, expected in cases.items():
            with mock.patch.dict(
                os.environ,
                {"NEUROCHIP_PYNQ_PREFLIGHT_TIMEOUT_SECONDS": raw},
                clear=False,
            ):
                self.assertEqual(
                    launcher_server._resolve_pynq_preflight_timeout(),
                    expected,
                    raw,
                )

    def test_provision_pynq_board_retries_preflight_timeout(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with (
            mock.patch.object(self.state, "_build_local_pynq_bundle"),
            mock.patch.object(self.state, "_run_ssh"),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                side_effect=[
                    launcher_server.RuntimeRequestError(
                        "Runtime request timed out for GET http://192.168.1.50:8002/hardware/pynq/preflight after 45s",
                        kind="timeout",
                        url="http://192.168.1.50:8002/hardware/pynq/preflight",
                    ),
                    {"board": {"state": "ready"}},
                ],
            ) as fetch_preflight,
            mock.patch("nmtk.launcher_control.server.time.sleep", return_value=None),
        ):
            result = self.state.provision_pynq_board(board["id"])

        self.assertEqual(result["board"]["state"], "ready")
        self.assertEqual(fetch_preflight.call_count, 2)

    def test_restart_pynq_runtime_rechecks_health_when_preflight_is_unreachable(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with (
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(self.state, "_run_ssh"),
            mock.patch.object(
                self.state,
                "_wait_for_board_agent_health",
            ) as wait_for_health,
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                side_effect=[
                    launcher_server.RuntimeRequestError(
                        "Runtime request failed for GET http://192.168.1.50:8002/hardware/pynq/preflight: could not be reached: connection refused",
                        kind="unreachable",
                        url="http://192.168.1.50:8002/hardware/pynq/preflight",
                    ),
                    {"board": {"state": "ready"}},
                ],
            ) as fetch_preflight,
            mock.patch("nmtk.launcher_control.server.time.sleep", return_value=None),
        ):
            result = self.state.restart_pynq_runtime(board["id"])

        self.assertEqual(result["board"]["state"], "ready")
        self.assertEqual(wait_for_health.call_count, 2)
        self.assertEqual(fetch_preflight.call_count, 2)

    def test_fetch_pynq_board_preflight_marks_overlay_missing_when_assets_are_missing(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with mock.patch.object(
            self.state,
            "_runtime_json_request",
            return_value={
                "preflight_status": "failed",
                "preflight_message": "Install Overlay next.",
                "runtime_mode": "hardware",
                "overlay_assets": {"ready_for_hardware": False},
            },
        ):
            result = self.state.fetch_pynq_board_preflight(board["id"])

        self.assertEqual(result["board"]["state"], "overlay_missing")

    def test_fetch_pynq_board_preflight_marks_ready_asset_failures_as_preflight_failed(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with mock.patch.object(
            self.state,
            "_runtime_json_request",
            return_value={
                "preflight_status": "failed",
                "preflight_message": (
                    "Runtime probe failed: No Devices Found. Checked bitstream path: "
                    "/home/xilinx/.local/share/neurochip-pynq-agent/overlays/snn_overlay.bit."
                ),
                "runtime_mode": "hardware",
                "overlay_assets": {"ready_for_hardware": True},
            },
        ):
            result = self.state.fetch_pynq_board_preflight(board["id"])

        self.assertEqual(result["board"]["state"], "preflight_failed")
        self.assertIn(
            "/home/xilinx/.local/share/neurochip-pynq-agent/overlays/snn_overlay.bit",
            result["board"]["lastPreflightMessage"],
        )

    def test_doctor_report_skips_not_installed_module_preflight(self) -> None:
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["notInstalled"]

        with mock.patch.object(self.state, "_preflight_module") as preflight:
            report = self.state.doctor_report()

        preflight.assert_not_called()
        self.assertEqual(report["modules"][0]["preflightMessage"], "Module not installed")

    def test_wrapper_runs_without_external_pythonpath(self) -> None:
        env = os.environ.copy()
        env.pop("PYTHONPATH", None)

        result = subprocess.run(
            [
                sys.executable,
                str(PROJECT_ROOT / "scripts" / "launcher_control_service.py"),
                "--help",
            ],
            cwd=self._tempdir.name,
            capture_output=True,
            text=True,
            env=env,
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
        self.assertIn("Launcher control service", result.stdout)

    def test_module_python_path_preserves_poetry_shim_path(self) -> None:
        self._write_poetry_pyproject()
        poetry_python, base_python = self._create_fake_inproject_poetry_python_symlink()
        module = self.state._get_module("dummy")

        python_path = launcher_server._module_python_path(module)
        expected_poetry_python = (
            (self.repo_root / "dummy_module").resolve() / ".venv" / "bin" / "python"
        )

        self.assertEqual(python_path, expected_poetry_python)
        self.assertTrue(python_path.samefile(poetry_python))
        self.assertNotEqual(python_path, base_python.resolve())

    def test_run_dev_script_passes_bash_syntax_check(self) -> None:
        result = subprocess.run(
            ["bash", "-n", str(PROJECT_ROOT / "scripts" / "run_dev.sh")],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)

    def test_start_module_uses_runtime_uvicorn_host_env(self) -> None:
        module_id = "dummy"

        class _FakeProcess:
            stdout = None
            stderr = None
            returncode = 0

            def poll(self) -> None:
                return None

            def wait(self, timeout=None) -> int:
                return 0

            def terminate(self) -> None:
                return None

            def kill(self) -> None:
                return None

        with (
            mock.patch.dict(os.environ, {"NMTK_UVICORN_HOST": "0.0.0.0"}, clear=False),
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_OK,
                    environment_fingerprint="fingerprint-1",
                ),
            ),
            mock.patch.object(self.state, "_kill_process_on_port"),
            mock.patch.object(self.state, "_stream_logs"),
            mock.patch.object(self.state, "_watch_process_exit"),
            mock.patch.object(self.state, "_probe_health", return_value=(True, 200, "ok")),
            mock.patch.object(launcher_server.subprocess, "Popen", return_value=_FakeProcess()) as popen,
        ):
            self.state._start_sync(module_id)

        command = popen.call_args.args[0]
        self.assertIn("--host", command)
        self.assertEqual(command[command.index("--host") + 1], "0.0.0.0")

    def test_start_module_fails_closed_on_preflight_failure(self) -> None:
        with (
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_FAILED,
                    message="Missing required dependency: fastapi (needed by app.main)",
                    environment_fingerprint="fingerprint-2",
                ),
            ),
            mock.patch.object(launcher_server.subprocess, "Popen") as popen,
        ):
            with self.assertRaises(RuntimeError):
                self.state._start_sync("dummy")

        popen.assert_not_called()
        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["error"])
        self.assertEqual(payload["preflightStatus"], launcher_server.PREFLIGHT_FAILED)
        self.assertIn("fastapi", payload["preflightMessage"])

    def test_start_module_preserves_optional_capability_warnings(self) -> None:
        class _FakeProcess:
            stdout = None
            stderr = None
            returncode = 0

            def poll(self) -> None:
                return None

            def wait(self, timeout=None) -> int:
                return 0

            def terminate(self) -> None:
                return None

            def kill(self) -> None:
                return None

        with (
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_DEGRADED,
                    message="Optional capability unavailable: lava.magma.core.run_conditions",
                    capability_warnings=[
                        "Optional capability unavailable: lava.magma.core.run_conditions"
                    ],
                    environment_fingerprint="fingerprint-3",
                ),
            ),
            mock.patch.object(self.state, "_kill_process_on_port"),
            mock.patch.object(self.state, "_stream_logs"),
            mock.patch.object(self.state, "_watch_process_exit"),
            mock.patch.object(self.state, "_probe_health", return_value=(True, 200, "ok")),
            mock.patch.object(launcher_server.subprocess, "Popen", return_value=_FakeProcess()),
        ):
            self.state._start_sync("dummy")

        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["degraded"])
        self.assertEqual(payload["preflightStatus"], launcher_server.PREFLIGHT_DEGRADED)
        self.assertEqual(
            payload["capabilityWarnings"],
            ["Optional capability unavailable: lava.magma.core.run_conditions"],
        )

    def test_start_module_requires_suite_api_ready_for_monolith_modules(self) -> None:
        module = self.state._get_module("dummy")
        module["startStrategy"] = "none"
        module["port"] = launcher_server.DEFAULT_SUITE_API_PORT  # monolith port
        self.state._manage_suite_api = True
        self.state._suite_api_status = launcher_server.SUITE_API_STATUS_PREFLIGHT_FAILED
        self.state._suite_api_message = "suite_api runtime dependencies are missing"

        with self.assertRaises(RuntimeError) as exc_info:
            self.state._start_sync("dummy")

        self.assertIn("suite_api runtime dependencies are missing", str(exc_info.exception))
        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["error"])
        self.assertEqual(payload["preflightStatus"], launcher_server.PREFLIGHT_FAILED)
        self.assertIn("suite_api", payload["preflightMessage"])

    def test_doctor_report_marks_fatal_preflight_as_blocking(self) -> None:
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["installed"]
        with (
            mock.patch.object(launcher_server, "_global_preflight_checks", return_value=[]),
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_FAILED,
                    message="Missing required dependency: fastapi (needed by app.main)",
                    environment_fingerprint="fingerprint-fatal",
                ),
            ),
        ):
            report = self.state.doctor_report()

        self.assertEqual(report["status"], "error")
        self.assertEqual(report["fatalCount"], 1)
        self.assertEqual(report["degradedCount"], 0)
        self.assertEqual(report["okCount"], 0)
        self.assertEqual(report["modules"][0]["preflightStatus"], launcher_server.PREFLIGHT_FAILED)
        self.assertIn("fastapi", report["modules"][0]["preflightMessage"])

    def test_doctor_report_marks_suite_api_failure_as_blocking_for_monolith_modules(
        self,
    ) -> None:
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["installed"]
        module["startStrategy"] = "none"
        module["port"] = launcher_server.DEFAULT_SUITE_API_PORT  # monolith port
        self.state._manage_suite_api = True
        self.state._suite_api_status = launcher_server.SUITE_API_STATUS_PREFLIGHT_FAILED
        self.state._suite_api_message = "suite_api port 9000 is occupied by another process"

        with mock.patch.object(launcher_server, "_global_preflight_checks", return_value=[]):
            report = self.state.doctor_report()

        self.assertEqual(report["status"], "error")
        self.assertEqual(report["fatalCount"], 1)
        self.assertEqual(report["modules"][0]["preflightStatus"], launcher_server.PREFLIGHT_FAILED)
        self.assertIn("port 9000", report["modules"][0]["preflightMessage"])

    def test_doctor_report_keeps_optional_capability_degradation_nonfatal(self) -> None:
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["installed"]
        with (
            mock.patch.object(launcher_server, "_global_preflight_checks", return_value=[]),
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_DEGRADED,
                    message="Optional capability unavailable: lava.magma.core.run_conditions",
                    capability_warnings=[
                        "Optional capability unavailable: lava.magma.core.run_conditions"
                    ],
                    environment_fingerprint="fingerprint-degraded",
                ),
            ),
        ):
            report = self.state.doctor_report()

        self.assertEqual(report["status"], "ok")
        self.assertEqual(report["fatalCount"], 0)
        self.assertEqual(report["degradedCount"], 1)
        self.assertEqual(report["okCount"], 0)
        self.assertEqual(
            report["modules"][0]["preflightStatus"],
            launcher_server.PREFLIGHT_DEGRADED,
        )
        self.assertEqual(
            report["modules"][0]["capabilityWarnings"],
            ["Optional capability unavailable: lava.magma.core.run_conditions"],
        )

    # ── Externally managed service (e.g. Jupyter) ──────────────────────────

    def test_start_sync_external_service_marks_running_when_healthy(self) -> None:
        """When an externally managed standalone service responds to health,
        _start_sync should mark it running without any suite_api interaction."""
        module = self.state._get_module("dummy")
        # Remove uvicornTarget so _module_start_strategy returns "none";
        # port 8123 != DEFAULT_SUITE_API_PORT so it becomes externally managed.
        module["uvicornTarget"] = ""
        module["startStrategy"] = "none"

        with mock.patch.object(
            self.state, "_probe_health", return_value=(True, 200, "healthy")
        ):
            self.state._start_sync("dummy")

        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["running"])
        self.assertEqual(payload["healthStatus"], "healthy")

    def test_start_sync_external_service_marks_error_when_not_reachable(self) -> None:
        """When an externally managed service is not reachable, _start_sync
        should raise RuntimeError and mark the module as error."""
        module = self.state._get_module("dummy")
        module["uvicornTarget"] = ""
        module["startStrategy"] = "none"
        module["deployment"] = {"composeProfile": "notebooks", "healthPath": "/api/status"}

        with (
            mock.patch.object(self.state, "_probe_health", return_value=(False, 0, None)),
            self.assertRaises(RuntimeError) as exc_info,
        ):
            self.state._start_sync("dummy")

        self.assertIn("notebooks", str(exc_info.exception))
        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["error"])
        self.assertIn("port", payload["healthStatus"])

    def test_start_sync_external_service_does_not_check_suite_api(self) -> None:
        """Externally managed services must not gate on suite_api readiness."""
        module = self.state._get_module("dummy")
        module["uvicornTarget"] = ""
        module["startStrategy"] = "none"
        self.state._manage_suite_api = True
        self.state._suite_api_status = launcher_server.SUITE_API_STATUS_PREFLIGHT_FAILED

        with mock.patch.object(
            self.state, "_probe_health", return_value=(True, 200, "ok")
        ):
            self.state._start_sync("dummy")

        payload = self.state.serialize_module("dummy")
        # Should be running despite suite_api being down
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["running"])

    def test_probe_health_uses_deployment_health_path_for_external_service(self) -> None:
        """_probe_health should use deployment.healthPath for externally managed
        services, not the monolith /api/<id>/health pattern."""
        module = self.state._get_module("dummy")
        module["uvicornTarget"] = ""
        module["startStrategy"] = "none"
        module["deployment"] = {"healthPath": "/api/status"}

        captured_urls: list[str] = []

        def fake_urlopen(url: str, timeout: float = 2.0) -> object:
            captured_urls.append(url)
            raise urllib.error.URLError("connection refused")

        with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
            self.state._probe_health(module)

        self.assertEqual(len(captured_urls), 1)
        self.assertIn("/api/status", captured_urls[0])
        self.assertNotIn(f"/api/{module['id']}/health", captured_urls[0])

    def test_doctor_report_external_service_reachable_is_ok(self) -> None:
        """doctor_report should report PREFLIGHT_OK for a reachable external service."""
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["installed"]
        module["uvicornTarget"] = ""
        module["startStrategy"] = "none"

        with (
            mock.patch.object(launcher_server, "_global_preflight_checks", return_value=[]),
            mock.patch.object(
                self.state, "_probe_health", return_value=(True, 200, "ok")
            ),
        ):
            report = self.state.doctor_report()

        self.assertEqual(report["modules"][0]["preflightStatus"], launcher_server.PREFLIGHT_OK)
        self.assertEqual(report["fatalCount"], 0)
        self.assertEqual(report["degradedCount"], 0)

    def test_doctor_report_external_service_not_reachable_is_degraded(self) -> None:
        """doctor_report should report PREFLIGHT_DEGRADED (not fatal) when an
        external service is not running — it is optional and externally managed."""
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["installed"]
        module["uvicornTarget"] = ""
        module["startStrategy"] = "none"
        module["deployment"] = {"composeProfile": "notebooks", "healthPath": "/api/status"}

        with (
            mock.patch.object(launcher_server, "_global_preflight_checks", return_value=[]),
            mock.patch.object(self.state, "_probe_health", return_value=(False, 0, None)),
        ):
            report = self.state.doctor_report()

        self.assertEqual(
            report["modules"][0]["preflightStatus"], launcher_server.PREFLIGHT_DEGRADED
        )
        self.assertIn("notebooks", report["modules"][0]["preflightMessage"])
        self.assertEqual(report["fatalCount"], 0)
        self.assertEqual(report["degradedCount"], 1)

    def test_health_poll_loop_recovers_external_service_from_error(self) -> None:
        """The health poll loop should transition an external service from error
        back to running when it becomes reachable again."""
        module = self.state._get_module("dummy")
        module["uvicornTarget"] = ""
        module["startStrategy"] = "none"
        module["status"] = launcher_server.STATUS_INDEX["error"]

        call_count = 0

        def probe_side_effect(m: dict) -> tuple[bool, int, str | None]:
            nonlocal call_count
            call_count += 1
            if launcher_server._is_externally_managed_service(m):
                return (True, 200, "recovered")
            return (False, 0, None)

        with (
            mock.patch.object(self.state, "_suite_api_health_probe" if False else "_probe_health",
                               side_effect=probe_side_effect),
            mock.patch.object(self.state, "_shutdown") as mock_shutdown,
        ):
            # Simulate one poll tick: wait returns False (not shut down), then True
            mock_shutdown.wait.side_effect = [False, True]
            self.state._manage_suite_api = False
            self.state._health_poll_loop()

        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["running"])
        self.assertEqual(payload["healthStatus"], "recovered")

    def test_doctor_report_handles_akida_hosts_without_cached_host_field(self) -> None:
        self.state._settings["akidaHosts"] = [
            {
                "id": "akida-1",
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
                "state": "ready",
                "lastPreflightStatus": launcher_server.PREFLIGHT_OK,
            }
        ]
        with (
            mock.patch.object(launcher_server, "_global_preflight_checks", return_value=[]),
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_OK,
                    message="ready",
                    environment_fingerprint="fingerprint-ok",
                ),
            ),
        ):
            report = self.state.doctor_report()

        self.assertEqual(report["status"], "ok")
        self.assertEqual(report["akidaHosts"][0]["host"], "akida-box.local")
        self.assertEqual(report["akidaHosts"][0]["baseUrl"], "http://akida-box.local:8002")

    def test_render_doctor_report_uses_explicit_policy_terms(self) -> None:
        report = {
            "status": "error",
            "fatalCount": 1,
            "degradedCount": 1,
            "okCount": 1,
            "globalChecks": [
                {
                    "id": "flutter-sdk",
                    "preflightStatus": launcher_server.PREFLIGHT_FAILED,
                    "preflightMessage": "Flutter SDK cache is not writable: /tmp/flutter/bin/cache",
                    "capabilityWarnings": [],
                }
            ],
            "modules": [
                {
                    "id": "fatal-module",
                    "preflightStatus": launcher_server.PREFLIGHT_FAILED,
                    "preflightMessage": "Missing required dependency: fastapi",
                    "capabilityWarnings": [],
                },
                {
                    "id": "degraded-module",
                    "preflightStatus": launcher_server.PREFLIGHT_DEGRADED,
                    "preflightMessage": "Optional capability unavailable: lava",
                    "capabilityWarnings": ["Optional capability unavailable: lava"],
                },
            ],
        }

        rendered = launcher_server._render_doctor_report(report)

        self.assertIn("status=preflight failed", rendered)
        self.assertIn("preflight failed flutter-sdk", rendered)
        self.assertIn("preflight failed fatal-module", rendered)
        self.assertIn("degraded optional capability degraded-module", rendered)

    def test_doctor_report_includes_global_preflight_failures(self) -> None:
        with (
            mock.patch.object(
                launcher_server,
                "_global_preflight_checks",
                return_value=[
                    {
                        "id": "flutter-sdk",
                        "name": "Flutter SDK",
                        "preflightStatus": launcher_server.PREFLIGHT_FAILED,
                        "preflightMessage": "Flutter SDK cache is not writable: /tmp/flutter/bin/cache",
                        "capabilityWarnings": [],
                    }
                ],
            ),
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_OK,
                    message=None,
                ),
            ),
        ):
            report = self.state.doctor_report()

        self.assertEqual(report["status"], "error")
        self.assertEqual(report["fatalCount"], 1)
        self.assertEqual(len(report["globalChecks"]), 1)
        self.assertEqual(report["globalChecks"][0]["id"], "flutter-sdk")

    def test_global_preflight_checks_flag_unwritable_flutter_cache(self) -> None:
        flutter_bin = self.repo_root / "flutter" / "bin" / "flutter"
        cache_dir = flutter_bin.parent / "cache"
        cache_dir.mkdir(parents=True, exist_ok=True)
        flutter_bin.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        engine_stamp = cache_dir / "engine.stamp"
        engine_stamp.write_text("ready\n", encoding="utf-8")
        resolved_cache_dir = cache_dir.resolve()
        resolved_engine_stamp = engine_stamp.resolve()

        def fake_access(path: str | os.PathLike[str], mode: int) -> bool:
            normalized = Path(path).resolve()
            if normalized in {resolved_cache_dir, resolved_engine_stamp}:
                return False
            return True

        with (
            mock.patch.object(launcher_server.shutil, "which", return_value=str(flutter_bin)),
            mock.patch.object(launcher_server.os, "access", side_effect=fake_access),
        ):
            checks = launcher_server._global_preflight_checks()

        self.assertEqual(len(checks), 1)
        self.assertEqual(checks[0]["preflightStatus"], launcher_server.PREFLIGHT_FAILED)
        self.assertIn("not writable", str(checks[0]["preflightMessage"]))

    def test_main_returns_nonzero_for_fatal_doctor_report(self) -> None:
        fake_state = mock.Mock()
        fake_state.doctor_report.return_value = {
            "status": "error",
            "fatalCount": 1,
            "degradedCount": 0,
            "okCount": 0,
            "modules": [],
        }

        stdout = io.StringIO()
        with (
            mock.patch.object(launcher_server, "LauncherControlState", return_value=fake_state),
            mock.patch.object(sys, "stdout", stdout),
        ):
            exit_code = launcher_server.main(["--doctor", "--json"])

        self.assertEqual(exit_code, 1)
        fake_state.shutdown.assert_called_once()
        self.assertEqual(json.loads(stdout.getvalue()), fake_state.doctor_report.return_value)

    def test_main_returns_zero_for_degraded_only_doctor_report(self) -> None:
        fake_state = mock.Mock()
        fake_state.doctor_report.return_value = {
            "status": "ok",
            "fatalCount": 0,
            "degradedCount": 1,
            "okCount": 0,
            "modules": [
                {
                    "id": "dummy",
                    "preflightStatus": launcher_server.PREFLIGHT_DEGRADED,
                    "preflightMessage": "Optional capability unavailable: lava",
                    "capabilityWarnings": ["Optional capability unavailable: lava"],
                }
            ],
        }

        stdout = io.StringIO()
        with (
            mock.patch.object(launcher_server, "LauncherControlState", return_value=fake_state),
            mock.patch.object(sys, "stdout", stdout),
        ):
            exit_code = launcher_server.main(["--doctor", "--json"])

        self.assertEqual(exit_code, 0)
        fake_state.shutdown.assert_called_once()
        self.assertEqual(json.loads(stdout.getvalue()), fake_state.doctor_report.return_value)

    def test_preflight_repairs_stale_environment_once(self) -> None:
        module = self.state._get_module("dummy")
        module["environmentFingerprint"] = "stale-fingerprint"

        with (
            mock.patch.object(
                launcher_server,
                "_module_venv_python",
                return_value=self._fake_venv_python,
            ),
            mock.patch.object(
                self.state,
                "_compute_environment_fingerprint",
                side_effect=["new-fingerprint", "repaired-fingerprint"],
            ),
            mock.patch.object(
                self.state,
                "_run_import_probe",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_OK,
                ),
            ),
            mock.patch.object(self.state, "_install_sync") as install_sync,
        ):
            result = self.state._preflight_module(module, allow_repair=True)

        install_sync.assert_called_once_with("dummy")
        self.assertEqual(result.status, launcher_server.PREFLIGHT_OK)
        self.assertEqual(result.environment_fingerprint, "repaired-fingerprint")

    def test_preflight_reinstalls_broken_env_once_then_returns_failure(self) -> None:
        module = self.state._get_module("dummy")

        with (
            mock.patch.object(
                launcher_server,
                "_module_venv_python",
                return_value=self._fake_venv_python,
            ),
            mock.patch.object(
                self.state,
                "_compute_environment_fingerprint",
                return_value="fingerprint-4",
            ),
            mock.patch.object(
                self.state,
                "_run_import_probe",
                side_effect=[
                    launcher_server.PreflightResult(
                        status=launcher_server.PREFLIGHT_FAILED,
                        message="Missing required dependency: fastapi (needed by app.main)",
                    ),
                    launcher_server.PreflightResult(
                        status=launcher_server.PREFLIGHT_FAILED,
                        message="Missing required dependency: fastapi (needed by app.main)",
                    ),
                ],
            ),
            mock.patch.object(self.state, "_install_sync") as install_sync,
        ):
            result = self.state._preflight_module(module, allow_repair=True)

        install_sync.assert_called_once_with("dummy")
        self.assertEqual(result.status, launcher_server.PREFLIGHT_FAILED)
        self.assertIn("fastapi", result.message)

    def test_preflight_accepts_recovered_poetry_probe_despite_stale_failed_fingerprint(self) -> None:
        self._write_poetry_pyproject()
        poetry_python = self.repo_root / "dummy_module" / ".venv" / "bin" / "python"
        poetry_python.parent.mkdir(parents=True, exist_ok=True)
        poetry_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        poetry_python.chmod(0o755)
        module = self.state._get_module("dummy")
        module["environmentFingerprint"] = "stale-fingerprint"
        module["preflightStatus"] = launcher_server.PREFLIGHT_FAILED
        module["preflightMessage"] = "Missing required dependency: fastapi (needed by app.main)"

        with (
            mock.patch.object(
                self.state,
                "_compute_environment_fingerprint",
                return_value="fresh-fingerprint",
            ),
            mock.patch.object(
                self.state,
                "_run_import_probe",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_OK,
                ),
            ) as run_import_probe,
            mock.patch.object(self.state, "_install_sync") as install_sync,
        ):
            result = self.state._preflight_module(module, allow_repair=False)

        install_sync.assert_not_called()
        run_import_probe.assert_called_once_with(module)
        self.assertEqual(result.status, launcher_server.PREFLIGHT_OK)
        self.assertEqual(result.environment_fingerprint, "fresh-fingerprint")

    def test_preflight_cleans_poetry_env_before_reinstalling_once(self) -> None:
        self._write_poetry_pyproject()
        poetry_python = self.repo_root / "dummy_module" / ".venv" / "bin" / "python"
        poetry_python.parent.mkdir(parents=True, exist_ok=True)
        poetry_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        poetry_python.chmod(0o755)
        module = self.state._get_module("dummy")

        with (
            mock.patch.object(
                self.state,
                "_compute_environment_fingerprint",
                side_effect=["fingerprint-before", "fingerprint-after"],
            ),
            mock.patch.object(
                self.state,
                "_run_import_probe",
                side_effect=[
                    launcher_server.PreflightResult(
                        status=launcher_server.PREFLIGHT_FAILED,
                        message="Missing required dependency: fastapi (needed by app.main)",
                    ),
                    launcher_server.PreflightResult(
                        status=launcher_server.PREFLIGHT_OK,
                    ),
                ],
            ) as run_import_probe,
            mock.patch.object(self.state, "_cleanup_module_environment") as cleanup_env,
            mock.patch.object(self.state, "_install_sync") as install_sync,
        ):
            result = self.state._preflight_module(module, allow_repair=True)

        cleanup_env.assert_called_once_with("dummy")
        install_sync.assert_called_once_with("dummy")
        self.assertEqual(run_import_probe.call_count, 2)
        self.assertEqual(result.status, launcher_server.PREFLIGHT_OK)
        self.assertEqual(result.environment_fingerprint, "fingerprint-after")

    def test_cleanup_module_environment_removes_disposable_poetry_artifacts(self) -> None:
        self._write_poetry_pyproject()
        install_dir = self.repo_root / "dummy_module"
        for venv_name in (".venv", "venv"):
            venv_python = install_dir / venv_name / "bin" / "python"
            venv_python.parent.mkdir(parents=True, exist_ok=True)
            venv_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            venv_python.chmod(0o755)
        poetry_toml = install_dir / "poetry.toml"
        poetry_toml.write_text("[virtualenvs]\nin-project = true\n", encoding="utf-8")
        fallback_env_root = self.repo_root / ".poetry-envs" / "dummy"
        fallback_python = fallback_env_root / "bin" / "python"
        fallback_python.parent.mkdir(parents=True, exist_ok=True)
        fallback_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        fallback_python.chmod(0o755)

        with (
            mock.patch.object(launcher_server, "_poetry_command", return_value="poetry"),
            mock.patch.object(launcher_server.subprocess, "run") as poetry_run,
        ):
            self.state._cleanup_module_environment("dummy")

        self.assertFalse((install_dir / ".venv").exists())
        self.assertFalse((install_dir / "venv").exists())
        self.assertFalse(poetry_toml.exists())
        self.assertFalse(fallback_env_root.exists())
        poetry_run.assert_called_once_with(
            ["poetry", "env", "remove", "--all"],
            cwd=install_dir.resolve(),
            capture_output=True,
            text=True,
            check=False,
        )

    def test_install_sync_uses_poetry_install_no_root_for_poetry_projects(self) -> None:
        self._write_poetry_pyproject()
        poetry_python = self._create_fake_poetry_python()

        with (
            mock.patch.object(launcher_server, "_poetry_command", return_value="poetry"),
            mock.patch.object(
                launcher_server.subprocess,
                "run",
                return_value=mock.Mock(returncode=0, stdout=str(poetry_python.parents[1]), stderr=""),
            ),
            mock.patch.object(self.state, "_run_command") as run_command,
            mock.patch.object(
                self.state,
                "_compute_environment_fingerprint",
                return_value="fingerprint-poetry",
            ),
        ):
            self.state._install_sync("dummy")

        self.assertEqual(
            run_command.call_args_list[-1].args[0],
            ["poetry", "install", "--no-interaction", "--no-root"],
        )

    def test_install_sync_uses_module_python_for_pip_commands_when_only_dotvenv_exists(
        self,
    ) -> None:
        install_dir = self.repo_root / "dummy_module"
        dotvenv_python = install_dir / ".venv" / "bin" / "python"
        dotvenv_python.parent.mkdir(parents=True, exist_ok=True)
        dotvenv_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        dotvenv_python.chmod(0o755)

        with (
            mock.patch.object(self.state, "_run_command") as run_command,
            mock.patch.object(
                self.state,
                "_compute_environment_fingerprint",
                return_value="fingerprint-dotvenv",
            ),
        ):
            self.state._install_sync("dummy")

        pip_calls = [
            call.args[0]
            for call in run_command.call_args_list
            if call.args and isinstance(call.args[0], list) and "pip" in call.args[0]
        ]
        self.assertTrue(
            any(
                call[:4] == [str(call[0]), "-m", "pip", "install"]
                and str(call[0]).endswith("/dummy_module/.venv/bin/python")
                and call[-1] == "."
                for call in pip_calls
            )
        )
        self.assertFalse(
            any(str(call[0]).endswith("/dummy_module/venv/bin/pip") for call in pip_calls)
        )

    def test_install_sync_bootstraps_pip_when_module_env_lacks_it(self) -> None:
        install_dir = self.repo_root / "dummy_module"
        dotvenv_python = install_dir / ".venv" / "bin" / "python"
        dotvenv_python.parent.mkdir(parents=True, exist_ok=True)
        dotvenv_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        dotvenv_python.chmod(0o755)

        subprocess_results = [
            mock.Mock(returncode=1, stdout="", stderr="No module named pip"),
            mock.Mock(returncode=0, stdout="bootstrapped", stderr=""),
            mock.Mock(returncode=0, stdout="pip 25.0", stderr=""),
        ]

        with (
            mock.patch.object(self.state, "_run_command") as run_command,
            mock.patch.object(
                self.state,
                "_compute_environment_fingerprint",
                return_value="fingerprint-pip-bootstrap",
            ),
            mock.patch.object(
                launcher_server.subprocess,
                "run",
                side_effect=subprocess_results,
            ) as subprocess_run,
        ):
            self.state._install_sync("dummy")

        ensurepip_call = [
            str(dotvenv_python.resolve()),
            "-m",
            "ensurepip",
            "--upgrade",
        ]
        self.assertEqual(subprocess_run.call_args_list[1].args[0], ensurepip_call)
        self.assertTrue(
            any(
                call.args[0][:4]
                == [str(dotvenv_python.resolve()), "-m", "pip", "install"]
                for call in run_command.call_args_list
            )
        )

    def test_stream_logs_echoes_stdout_and_stderr_to_terminal(self) -> None:
        module_id = "dummy"

        class _FakeProcess:
            def __init__(self) -> None:
                self.stdout = io.StringIO("ready\n")
                self.stderr = io.StringIO("boom\n")

        managed = launcher_server.ManagedProcess(
            process=_FakeProcess(),
            logs=self.state._logs[module_id],
        )

        with self.state._lock:
            self.state._processes[module_id] = managed

        stdout = io.StringIO()
        stderr = io.StringIO()
        with (
            mock.patch.object(sys, "stdout", stdout),
            mock.patch.object(sys, "stderr", stderr),
        ):
            self.state._stream_logs(module_id, managed)
            deadline = time.time() + 2.0
            while time.time() < deadline:
                logs = list(self.state.get_logs(module_id)["lines"])
                if "[stderr] boom" in logs and "ready" in logs:
                    break
                time.sleep(0.01)

        self.assertIn("ready", self.state.get_logs(module_id)["lines"])
        self.assertIn("[stderr] boom", self.state.get_logs(module_id)["lines"])
        self.assertIn("[dummy] ready", stdout.getvalue())
        self.assertIn("[dummy] boom", stderr.getvalue())

    def test_deployment_target_persists_without_plaintext_secret(self) -> None:
        target = self.state.create_deployment_target(
            {
                "displayName": "Remote backend",
                "targetType": "remote_host",
                "mode": "standalone",
                "authMode": "ssh_password",
                "host": "192.0.2.10",
                "username": "nmtk",
                "password": "super-secret",
            }
        )

        self.assertEqual(target["displayName"], "Remote backend")
        self.assertEqual(target["secretRefs"]["password"][:12], "file-secret:")
        state_text = launcher_server.DEPLOYMENT_STATE_FILE.read_text(encoding="utf-8")
        secret_text = launcher_server.DEPLOYMENT_SECRET_FILE.read_text(encoding="utf-8")
        self.assertNotIn("super-secret", state_text)
        self.assertIn("super-secret", secret_text)

    def test_deployment_preflight_reports_local_standalone_ready(self) -> None:
        result = self.state.deployment_preflight(
            {
                "target": {
                    "displayName": "This machine",
                    "targetType": "local",
                    "mode": "standalone",
                    "backendPort": 65530,
                }
            }
        )

        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["message"], "preflight ready")

    def test_deployment_job_records_progress_events(self) -> None:
        target = self.state.create_deployment_target(
            {
                "displayName": "This machine",
                "targetType": "local",
                "mode": "standalone",
                "backendPort": 65531,
            }
        )

        job = self.state.create_deployment_job({"targetId": target["id"]})
        deadline = time.time() + 3.0
        while time.time() < deadline:
            job = self.state.get_deployment_job(job["id"])
            if job["stage"] in {"completed", "failed"}:
                break
            time.sleep(0.05)

        self.assertEqual(job["stage"], "completed")
        self.assertGreaterEqual(len(job["events"]), 3)
        sse_events = self.state.deployment_job_events(job["id"])
        self.assertTrue(sse_events[0].startswith("event: progress"))
        settings = self.state.get_settings()
        self.assertTrue(settings["backendDeploymentReady"])
        self.assertEqual(
            settings["selectedBackendDeploymentTarget"]["lastReadiness"],
            "ready",
        )

    def test_all_logs_endpoint_returns_aggregated_lines(self) -> None:
        server = launcher_server.create_server("127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 1.0)

        server.state._append_log("dummy", "stdout line", emit_terminal=False)
        server.state._append_log("dummy", "stderr line", stderr=True, emit_terminal=False)
        server.state._suite_api_logs.append("suite stdout")
        server.state._suite_api_logs.append("[stderr] suite stderr")

        request = urllib.request.Request(
            f"http://127.0.0.1:{server.server_address[1]}/api/launcher/logs"
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            payload = json.loads(response.read().decode("utf-8"))

        lines = payload["lines"]
        self.assertTrue(any("[suite_api] suite stdout" in line for line in lines))
        self.assertTrue(any("[suite_api] [stderr] suite stderr" in line for line in lines))
        self.assertTrue(any("[dummy] stdout line" in line for line in lines))
        self.assertTrue(any("[dummy] [stderr] stderr line" in line for line in lines))

    def test_all_logs_filter_error_only_returns_stderr_lines(self) -> None:
        server = launcher_server.create_server("127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 1.0)

        server.state._append_log("dummy", "stdout line", emit_terminal=False)
        server.state._append_log("dummy", "stderr line", stderr=True, emit_terminal=False)
        server.state._suite_api_logs.append("suite stdout")
        server.state._suite_api_logs.append("[stderr] suite stderr")

        request = urllib.request.Request(
            f"http://127.0.0.1:{server.server_address[1]}/api/launcher/logs?filter=error"
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            payload = json.loads(response.read().decode("utf-8"))

        lines = payload["lines"]
        self.assertTrue(any("[suite_api] [stderr] suite stderr" in line for line in lines))
        self.assertTrue(any("[dummy] [stderr] stderr line" in line for line in lines))
        self.assertFalse(any("stdout line" in line for line in lines))


    def test_k8s_manifest_renderer_produces_ordered_files(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_k8s_renderer import render_manifests

        target = DeploymentTarget(
            id="k8s-test",
            display_name="K8s Test",
            target_type="kubernetes_cluster",
            mode="kubernetes",
            namespace="nmtk-test",
            backend_port=9000,
            image_tag="v1.2.3",
        )
        manifests = render_manifests(
            target,
            app_name="nmtk-suite-api",
            image="ghcr.io/completed-spoon-6/neurocnl",
            env={"LOG_LEVEL": "info"},
            secret_env={"API_KEY": "secret-value"},
        )

        self.assertEqual(
            list(manifests.keys()),
            ["00-namespace.yaml", "01-configmap.yaml", "02-secret.yaml", "03-deployment.yaml", "04-service.yaml"],
        )
        self.assertIn("name: nmtk-test", manifests["00-namespace.yaml"])
        self.assertIn("LOG_LEVEL: info", manifests["01-configmap.yaml"])
        self.assertIn("API_KEY: secret-value", manifests["02-secret.yaml"])
        self.assertIn("image: ghcr.io/completed-spoon-6/neurocnl:v1.2.3", manifests["03-deployment.yaml"])
        self.assertIn("imagePullPolicy: IfNotPresent", manifests["03-deployment.yaml"])
        self.assertIn("type: LoadBalancer", manifests["04-service.yaml"])

    def test_k8s_manifest_renderer_includes_ingress_when_domain_set(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_k8s_renderer import render_manifests

        target = DeploymentTarget(
            id="k8s-test",
            display_name="K8s Test",
            target_type="kubernetes_cluster",
            mode="kubernetes",
            namespace="nmtk-test",
            domain="nmtk.example.com",
            backend_port=9000,
        )
        manifests = render_manifests(target, app_name="nmtk-suite-api")
        self.assertIn("05-ingress.yaml", manifests)
        self.assertIn("host: nmtk.example.com", manifests["05-ingress.yaml"])
        self.assertIn("type: ClusterIP", manifests["04-service.yaml"])

    def test_k8s_executor_runs_kubectl_commands(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import KubernetesDeploymentExecutor

        target = DeploymentTarget(
            id="k8s-exec",
            display_name="K8s Exec",
            target_type="kubernetes_cluster",
            mode="kubernetes",
            namespace="nmtk-test",
            backend_port=9000,
        )
        executor = KubernetesDeploymentExecutor(repo_root=self.repo_root)
        events: list[tuple[str, str, float]] = []

        def emit(stage: str, message: str, percent: float) -> None:
            events.append((stage, message, percent))

        with mock.patch("nmtk.launcher_control.deployment_executors.shutil.which") as mock_which, \
             mock.patch("nmtk.launcher_control.deployment_executors.subprocess.run") as mock_run, \
             mock.patch("nmtk.launcher_control.deployment_executors.urllib.request.urlopen") as mock_urlopen:
            mock_which.return_value = "/usr/local/bin/kubectl"
            mock_run.return_value = mock.Mock(returncode=0, stdout="", stderr="")
            mock_urlopen.return_value.__enter__ = mock.Mock(return_value=mock.Mock(status=200))
            mock_urlopen.return_value.__exit__ = mock.Mock(return_value=False)

            executor.run(target, emit)

        self.assertEqual(events[-1][0], "completed")
        self.assertIn("Validating Kubernetes cluster access", [e[1] for e in events])
        self.assertIn("Applying namespace-scoped backend resources", [e[1] for e in events])
        self.assertIn("Waiting for rollout readiness", [e[1] for e in events])
        self.assertIn("Running backend health verification", [e[1] for e in events])

        apply_calls = [c for c in mock_run.call_args_list if "apply" in str(c)]
        rollout_calls = [c for c in mock_run.call_args_list if "rollout" in str(c)]
        self.assertEqual(len(apply_calls), 1)
        self.assertEqual(len(rollout_calls), 1)

    def test_k8s_preflight_blocks_without_kubectl(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_preflight import run_preflight

        target = DeploymentTarget(
            id="k8s-pf",
            display_name="K8s PF",
            target_type="kubernetes_cluster",
            mode="kubernetes",
            namespace="nmtk-test",
        )
        with mock.patch("nmtk.launcher_control.deployment_preflight.shutil.which") as mock_which:
            mock_which.return_value = None
            result = run_preflight(target, repo_root=self.repo_root)

        self.assertEqual(result.status, "failed")
        self.assertIn("kubectl is not installed", result.message)

    def test_k8s_preflight_degrades_missing_namespace(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_preflight import run_preflight

        target = DeploymentTarget(
            id="k8s-pf",
            display_name="K8s PF",
            target_type="kubernetes_cluster",
            mode="kubernetes",
        )
        with mock.patch("nmtk.launcher_control.deployment_preflight.shutil.which") as mock_which, \
             mock.patch("nmtk.launcher_control.deployment_preflight.subprocess.run") as mock_run:
            mock_which.return_value = "/usr/local/bin/kubectl"
            mock_run.side_effect = [
                mock.Mock(returncode=0, stdout="minikube", stderr=""),
                mock.Mock(returncode=0, stdout="Kubernetes control plane", stderr=""),
            ]
            result = run_preflight(target, repo_root=self.repo_root)

        self.assertEqual(result.status, "degraded")
        self.assertTrue(
            any("namespace defaults to current context" in f for f in result.degraded_findings)
        )


class TestConfigPaths(unittest.TestCase):
    def test_default_paths_use_repo_root(self):
        """Without env vars set, all paths fall under REPO_ROOT."""
        import nmtk.launcher_control.config as cfg
        import importlib
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("NMTK_STATE_DIR", None)
            os.environ.pop("NMTK_DATA_DIR", None)
            importlib.reload(cfg)
            assert cfg.STATE_FILE.is_relative_to(PROJECT_ROOT)
            assert cfg.SETTINGS_FILE.is_relative_to(PROJECT_ROOT)
            assert cfg.WORKSPACE_FILE.is_relative_to(PROJECT_ROOT)
            assert cfg.DEPLOYMENT_STATE_FILE.is_relative_to(PROJECT_ROOT)
            assert cfg.DEPLOYMENT_SECRET_FILE.is_relative_to(PROJECT_ROOT)
            assert cfg.SUITE_API_ENV_ROOT.is_relative_to(PROJECT_ROOT)
            assert cfg.MODULES_MANIFEST.is_relative_to(PROJECT_ROOT)

    def test_nmtk_state_dir_overrides_state_files(self):
        """NMTK_STATE_DIR redirects the 4 module/workspace/settings state files."""
        import nmtk.launcher_control.config as cfg
        import importlib
        with tempfile.TemporaryDirectory() as state_dir:
            with mock.patch.dict(os.environ, {"NMTK_STATE_DIR": state_dir}):
                importlib.reload(cfg)
                assert str(cfg.STATE_FILE).startswith(state_dir)
                assert str(cfg.SETTINGS_FILE).startswith(state_dir)
                assert str(cfg.WORKSPACE_FILE).startswith(state_dir)
                assert str(cfg.DEPLOYMENT_STATE_FILE).startswith(state_dir)

    def test_nmtk_data_dir_overrides_secrets(self):
        """NMTK_DATA_DIR redirects deployment_secrets and suite_api_env."""
        import nmtk.launcher_control.config as cfg
        import importlib
        with tempfile.TemporaryDirectory() as data_dir:
            with mock.patch.dict(os.environ, {"NMTK_DATA_DIR": data_dir}):
                importlib.reload(cfg)
                assert str(cfg.DEPLOYMENT_SECRET_FILE).startswith(data_dir)
                assert str(cfg.SUITE_API_ENV_ROOT).startswith(data_dir)


if __name__ == "__main__":
    unittest.main()
