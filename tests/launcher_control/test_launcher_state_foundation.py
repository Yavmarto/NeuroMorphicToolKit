"""Contract tests for the typed launcher state foundation."""

from __future__ import annotations

import ast
import json
import subprocess
import sys

from base import PROJECT_ROOT, LauncherControlServiceTestBase

import nmtk.launcher_control.hardware_models as hardware_models
import nmtk.launcher_control.server as launcher_server
import nmtk.launcher_control.state_contracts as state_contracts


class TestLauncherStateFoundation(LauncherControlServiceTestBase):
    def test_internal_services_do_not_import_server_facade(self) -> None:
        launcher_root = PROJECT_ROOT / "nmtk" / "launcher_control"
        offenders: list[str] = []
        for path in sorted(launcher_root.glob("*.py")):
            if path.name in {"__init__.py", "server.py"}:
                continue
            tree = ast.parse(path.read_text(encoding="utf-8"))
            if any(
                isinstance(node, ast.ImportFrom) and node.module == "server"
                for node in ast.walk(tree)
            ):
                offenders.append(path.name)
        self.assertEqual(offenders, [])

    def test_service_submodule_import_does_not_initialize_server(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                "-c",
                (
                    "import sys; "
                    "import nmtk.launcher_control.settings_service; "
                    "print('nmtk.launcher_control.server' in sys.modules)"
                ),
            ],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertEqual(result.stdout.strip(), "False")

    def test_server_keeps_compatibility_exports(self) -> None:
        self.assertIs(launcher_server.STATUS_INDEX, state_contracts.STATUS_INDEX)
        self.assertIs(
            launcher_server.RuntimeRequestError,
            hardware_models.RuntimeRequestError,
        )
        self.assertIs(
            launcher_server.AkidaLauncherRuntimeContract,
            hardware_models.AkidaLauncherRuntimeContract,
        )

    def test_hardware_settings_persist_and_serialize_identically_after_restart(
        self,
    ) -> None:
        akida = self.state.create_akida_host(
            {
                "displayName": "Typed Akida",
                "host": "akida.example.test",
                "runtimeMode": "remote_sdk",
                "state": "ready",
            }
        )
        pynq = self.state.create_pynq_board(
            {
                "displayName": "Typed PYNQ",
                "host": "pynq.example.test",
                "state": "reachable",
            }
        )
        before = self.state.get_settings()
        persisted_path = (
            self.repo_root / "nmtk" / "neuro_toolkit" / "launcher_settings.json"
        )
        persisted_before = json.loads(persisted_path.read_text(encoding="utf-8"))

        self.state.shutdown()
        self.state = launcher_server.LauncherControlState(
            remote_version_resolver=self._resolve_remote_version
        )

        after = self.state.get_settings()
        persisted_after = json.loads(persisted_path.read_text(encoding="utf-8"))
        self.assertEqual(after, before)
        self.assertEqual(persisted_after, persisted_before)
        self.assertEqual(after["selectedAkidaHostId"], akida["id"])
        self.assertEqual(after["selectedPynqBoardId"], pynq["id"])
        self.assertNotIn("password", after["akidaHosts"][0])
        self.assertNotIn("password", after["pynqBoards"][0])
