"""Architecture and safety tests for the split Akida launcher services."""

from __future__ import annotations

import subprocess
import threading
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

import nmtk.launcher_control.akida_remote_client as remote_client_module
from nmtk.launcher_control.akida_host_repository import AkidaHostRepository
from nmtk.launcher_control.akida_preflight import evaluate_akida_preflight
from nmtk.launcher_control.akida_remote_client import AkidaRemoteClient
from nmtk.launcher_control.state_contracts import LauncherSettingsRecord


class _RemoteOwner:
    def __init__(self) -> None:
        self.token = ""
        self.updates: list[tuple[str, dict[str, Any]]] = []

    def _read_remote_akida_token(
        self,
        host: dict[str, Any],
        *,
        install_status: dict[str, Any] | None = None,
    ) -> str:
        del host, install_status
        return self.token

    def _update_akida_host_fields(self, host_id: str, **fields: Any) -> dict[str, Any]:
        self.updates.append((host_id, fields))
        return {"id": host_id, **fields}


class _EmptyStream:
    def readline(self) -> str:
        return ""

    def close(self) -> None:
        return None


class _TimedOutProcess:
    stdout = _EmptyStream()
    stderr = _EmptyStream()

    def __init__(self) -> None:
        self.killed = False

    def wait(self, timeout: float | None = None) -> int:
        if not self.killed:
            raise subprocess.TimeoutExpired(["ssh"], timeout)
        return -9

    def kill(self) -> None:
        self.killed = True


class TestAkidaHostRepository(unittest.TestCase):
    def test_crud_preserves_settings_shape_and_redacts_password(self) -> None:
        settings: LauncherSettingsRecord = {
            "logLevel": "info",
            "mujocoAvailable": False,
            "pythonAvailable": True,
            "akidaHosts": [],
            "akidaRuntimeUpdateJobs": [],
            "pynqBoards": [],
            "selectedAkidaHostId": None,
            "selectedPynqBoardId": None,
        }
        persist_calls: list[None] = []
        repository = AkidaHostRepository(
            settings=settings,
            lock=threading.RLock(),
            persist=lambda: persist_calls.append(None),
        )

        created = repository.create(
            {
                "id": "akida-1",
                "host": "akida.local",
                "username": "operator",
                "authMode": "password",
                "password": "secret-value",
                "isDefault": True,
            }
        )

        self.assertNotIn("password", created)
        self.assertTrue(created["hasPassword"])
        self.assertEqual(settings["akidaHosts"][0]["password"], "secret-value")
        self.assertEqual(settings["selectedAkidaHostId"], "akida-1")

        updated = repository.update("akida-1", {"password": ""})
        self.assertFalse(updated["hasPassword"])
        repository.delete("akida-1")
        self.assertEqual(settings["akidaHosts"], [])
        self.assertIsNone(settings["selectedAkidaHostId"])
        self.assertEqual(len(persist_calls), 3)


class TestAkidaPreflightEvaluator(unittest.TestCase):
    def test_hardware_runtime_upgrades_degraded_evidence_to_ready(self) -> None:
        evaluation = evaluate_akida_preflight(
            {"username": "operator"},
            {
                "preflight_status": "degraded",
                "preflight_message": "SDK still loading",
                "runtime_target": "software_fallback",
                "sdk_status": "loading",
            },
            runtime_status={
                "sdk_available": True,
                "sdk_status": "deployable",
                "runtime_target": "hardware",
                "sdk_issues": [],
            },
        )

        self.assertEqual(evaluation.status, "ok")
        self.assertEqual(evaluation.state, "ready")
        self.assertEqual(
            evaluation.readiness_message, "Akida hardware runtime is ready."
        )

    def test_user_space_install_remains_degraded_and_sanitizes_driver_output(
        self,
    ) -> None:
        evaluation = evaluate_akida_preflight(
            {"username": "operator"},
            {
                "preflight_status": "ok",
                "preflight_message": "Error reading 0xf0000010: err(110)",
                "runtime_target": "hardware",
                "sdk_status": "deployable",
            },
            install_status={"installMode": "user-space"},
        )

        self.assertEqual(evaluation.state, "degraded_optional_capability")
        self.assertNotIn("0xf0000010", evaluation.readiness_message)
        self.assertNotIn("err(110)", evaluation.readiness_message)


class TestAkidaRemoteClient(unittest.TestCase):
    def setUp(self) -> None:
        self.owner = _RemoteOwner()
        self.client = AkidaRemoteClient(self.owner)
        self.host: dict[str, Any] = {
            "id": "akida-1",
            "displayName": "Lab Akida",
            "host": "akida.local",
            "username": "operator",
            "authMode": "password",
            "password": "secret-value",
            "credentialRef": "api-token-value",
            "sshPort": 22,
        }

    def test_sshpass_uses_environment_instead_of_password_argv(self) -> None:
        with mock.patch.object(
            remote_client_module.shutil,
            "which",
            return_value="/usr/bin/sshpass",
        ):
            command, env, cleanup = self.client.prepare_ssh_invocation(self.host)

        self.assertIn("sshpass", command[0])
        self.assertIn("-e", command)
        self.assertNotIn("secret-value", command)
        self.assertIsNotNone(env)
        assert env is not None
        self.assertEqual(env["SSHPASS"], "secret-value")
        self.assertIsNone(cleanup)

    def test_ssh_timeout_kills_the_process_and_returns_no_secret(self) -> None:
        process = _TimedOutProcess()
        with (
            mock.patch.object(
                remote_client_module.shutil,
                "which",
                return_value="/usr/bin/sshpass",
            ),
            mock.patch.object(
                remote_client_module.subprocess,
                "Popen",
                return_value=process,
            ),self.assertRaisesRegex(RuntimeError, "timed out after 1s") as caught
        ):
            self.client.run_ssh(self.host, "sleep 10", timeout=1)

        self.assertTrue(process.killed)
        self.assertNotIn("secret-value", str(caught.exception))
        self.assertNotIn("api-token-value", str(caught.exception))

    def test_structured_logs_redact_password_and_api_token(self) -> None:
        with self.assertLogs(remote_client_module.LOGGER, level="ERROR") as captured:
            self.client.emit_log(
                self.host,
                "failed with secret-value and api-token-value",
                stderr=True,
            )

        detail = str(captured.records[0].message_detail)
        self.assertEqual(detail, "failed with <redacted> and <redacted>")


class TestAkidaModuleBoundaries(unittest.TestCase):
    def test_internal_components_do_not_import_the_server_facade(self) -> None:
        launcher_dir = Path(remote_client_module.__file__).resolve().parent
        for filename in (
            "akida_host_repository.py",
            "akida_preflight.py",
            "akida_remote_client.py",
            "akida_runtime_proxy.py",
            "akida_provisioning.py",
        ):
            source = (launcher_dir / filename).read_text(encoding="utf-8")
            self.assertNotIn("from .server", source, filename)
            self.assertNotIn("import nmtk.launcher_control.server", source, filename)


if __name__ == "__main__":
    unittest.main()
