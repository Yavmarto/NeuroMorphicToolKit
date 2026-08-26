"""Launcher control service tests: TestLauncherManifestWorkspace."""

from typing import Any
import json
import nmtk.launcher_control.hardware_models as launcher_hardware_models
import nmtk.launcher_control.server as launcher_server
import nmtk.launcher_control.suite_api_service as suite_api_service
from unittest import mock
import os
import sys
from base import LauncherControlServiceTestBase


class TestLauncherManifestWorkspace(LauncherControlServiceTestBase):
    def test_suite_api_url_uses_compose_network_override(self) -> None:
        with mock.patch.dict(
            os.environ,
            {"NMTK_SUITE_API_URL": "http://suite_api:9000/"},
            clear=False,
        ):
            self.assertEqual(
                suite_api_service._suite_api_base_url(), "http://suite_api:9000"
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

    def test_serialize_modules_refresh_updates_uses_remote_version_resolver(
        self,
    ) -> None:
        self._resolved_versions["dummy"] = "1.2.0"

        payload = self.state.serialize_modules(refresh_updates=True)

        self.assertEqual(payload[0]["remoteVersion"], "1.2.0")
        self.assertEqual(self._resolver_calls, ["dummy"])

    def test_refresh_remote_versions_ignores_older_versions(self) -> None:
        self._resolved_versions["dummy"] = "0.9.0"

        payload = self.state.serialize_modules(refresh_updates=True)

        self.assertEqual(payload[0]["remoteVersion"], "1.0.0")

    def test_refresh_remote_versions_keeps_last_known_update_when_lookup_fails(
        self,
    ) -> None:
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
            mock.patch.dict(
                os.environ, {"NMTK_SUITE_API_ENV_DIR": str(env_dir)}, clear=False
            ),
            mock.patch.object(
                suite_api_service,
                "_suite_api_env_fingerprint",
                return_value=fingerprint,
            ),
            mock.patch.object(
                suite_api_service,
                "_suite_api_dev_install_paths",
                return_value=(suite_api_dir,),
            ),
            mock.patch(
                "nmtk.launcher_control.suite_api_service.subprocess.run",
                side_effect=fake_run,
            ),
        ):
            python_path = self.state._suite_api_python()

        self.assertTrue(python_path.endswith("venv/bin/python"))
        self.assertEqual(install_targets, [str(suite_api_dir)])

    def test_suite_api_python_degrades_studio_extra_when_unavailable(self) -> None:
        neurocnl_dir = self.repo_root / "neurocnl"
        neurocnl_dir.mkdir(parents=True, exist_ok=True)
        other_dir = self.repo_root / "Neurohub"
        other_dir.mkdir(parents=True, exist_ok=True)

        env_dir = self.repo_root / ".nmtk" / "suite_api_env"
        env_dir.mkdir(parents=True, exist_ok=True)
        stamp_path = launcher_server._suite_api_env_stamp(env_dir)
        fingerprint = "test-fingerprint"
        stamp_path.write_text(json.dumps({"fingerprint": "stale"}), encoding="utf-8")

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
                target = args[-1]
                install_targets.append(target)
                if "studio" in target:
                    return mock.Mock(
                        returncode=1,
                        stdout="",
                        stderr="ERROR: Could not find a version that satisfies the "
                        "requirement akida>=2.19.1",
                    )
                return mock.Mock(returncode=0, stdout="", stderr="")
            self.fail(f"Unexpected subprocess.run call: {args}")

        with (
            mock.patch.dict(
                os.environ, {"NMTK_SUITE_API_ENV_DIR": str(env_dir)}, clear=False
            ),
            mock.patch.object(
                suite_api_service,
                "_suite_api_env_fingerprint",
                return_value=fingerprint,
            ),
            mock.patch.object(
                suite_api_service,
                "_suite_api_dev_install_paths",
                return_value=(neurocnl_dir, other_dir),
            ),
            mock.patch(
                "nmtk.launcher_control.suite_api_service.subprocess.run",
                side_effect=fake_run,
            ),
        ):
            python_path = self.state._suite_api_python()

        self.assertTrue(python_path.endswith("venv/bin/python"))
        # Full extras attempted, then the core-only retry, then the next checkout —
        # one optional extra failing must not abort the rest of the install loop.
        self.assertEqual(len(install_targets), 3)
        self.assertIn("studio", install_targets[0])
        self.assertNotIn("studio", install_targets[1])
        self.assertEqual(install_targets[2], str(other_dir))

        stamp_data = json.loads(stamp_path.read_text(encoding="utf-8"))
        self.assertEqual(stamp_data["fingerprint"], fingerprint)
        self.assertEqual(len(stamp_data["capabilityWarnings"]), 1)
        self.assertIn("akida", stamp_data["capabilityWarnings"][0])

    def test_resolved_lava_worker_url_uses_local_health_probe(self) -> None:
        with (
            mock.patch.dict(os.environ, {}, clear=True),
            mock.patch.object(
                launcher_hardware_models,
                "_lava_backend_reachable",
                return_value=True,
            ),
        ):
            resolved = launcher_server._resolved_lava_worker_url()
        self.assertEqual(resolved, "http://127.0.0.1:8012")

    def test_doctor_includes_studio_framework_sdk_check(self) -> None:
        report = self.state.doctor_report()
        check_ids = {check["id"] for check in report["globalChecks"]}
        self.assertIn("studio-framework-sdks", check_ids)

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
        self.assertEqual(
            payload["status"], launcher_server.STATUS_INDEX["notInstalled"]
        )
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
                self.repo_root / "nmtk" / "neuro_toolkit" / "module_states.json"
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
                self.repo_root / "nmtk" / "neuro_toolkit" / "workspace_state.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(persisted["focusedModuleId"], "dummy")
        self.assertEqual(
            persisted["sessions"][0]["restoreState"]["panel"], "validation"
        )

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

    def test_workspace_update_stays_usable_when_preferences_cannot_persist(
        self,
    ) -> None:
        with (
            mock.patch(
                "nmtk.launcher_control.workspace_service._write_workspace",
                side_effect=PermissionError("state volume is read-only"),
            ),
            self.assertLogs(
                "nmtk.launcher_control.workspace_service", level="WARNING"
            ) as logs,
        ):
            updated = self.state.create_workspace_session({"moduleId": "dummy"})

        self.assertEqual(updated["focusedModuleId"], "dummy")
        self.assertEqual(updated["sessions"][0]["moduleId"], "dummy")
        self.assertIn("could not be persisted", "\n".join(logs.output))

    def test_workspace_reload_restores_saved_sessions(self) -> None:
        workspace_file = (
            self.repo_root / "nmtk" / "neuro_toolkit" / "workspace_state.json"
        )
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

    def test_workspace_session_normalizes_legacy_neurosim_module_and_deep_link(
        self,
    ) -> None:
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
        self.assertEqual(
            created["sessions"][0]["deepLink"], "/canvas/projects?view=recent"
        )

    def test_workspace_reload_normalizes_legacy_neurosim_focus_and_canvas_routes(
        self,
    ) -> None:
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

        workspace_file = (
            self.repo_root / "nmtk" / "neuro_toolkit" / "workspace_state.json"
        )
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
        self.assertEqual(
            workspace["sessions"][0]["deepLink"], "/canvas/export?target=python"
        )
