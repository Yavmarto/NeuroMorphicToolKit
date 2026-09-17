"""Release-artifact and persistent Akida runtime update tests."""

from __future__ import annotations

import json
import os
import threading
import zipfile
from pathlib import Path
from unittest import mock

from base import LauncherControlServiceTestBase

from nmtk.launcher_control.runtime_artifact import (
    discover_neurochip_runtime_artifact,
    write_neurochip_runtime_artifact_manifest,
)


def _write_wheel(directory: Path, version: str = "0.6.0") -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    wheel_path = directory / f"neurochip-{version}-py3-none-any.whl"
    with zipfile.ZipFile(wheel_path, "w") as wheel:
        wheel.writestr(
            f"neurochip-{version}.dist-info/METADATA",
            f"Metadata-Version: 2.1\nName: neurochip\nVersion: {version}\n",
        )
    write_neurochip_runtime_artifact_manifest(directory)
    return wheel_path


class TestLauncherAkidaRuntimeUpdates(LauncherControlServiceTestBase):
    def setUp(self) -> None:
        super().setUp()
        self.artifact_dir = self.repo_root / "artifacts" / "neurochip"
        self.wheel_path = _write_wheel(self.artifact_dir)
        self.environment = mock.patch.dict(
            os.environ,
            {"NMTK_NEUROCHIP_ARTIFACT_DIR": str(self.artifact_dir)},
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def _host(self) -> dict[str, object]:
        return self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "203.0.113.90",
                "username": "dev",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/test-key",
            }
        )

    def test_artifact_manifest_verifies_version_and_checksum(self) -> None:
        artifact = discover_neurochip_runtime_artifact(self.artifact_dir)

        self.assertEqual(artifact.version, "0.6.0")
        self.assertEqual(len(artifact.sha256), 64)
        manifest = json.loads(
            (self.artifact_dir / "artifact-manifest.json").read_text(encoding="utf-8")
        )
        self.assertEqual(manifest["sha256"], artifact.sha256)

        self.wheel_path.write_bytes(self.wheel_path.read_bytes() + b"tampered")
        with self.assertRaisesRegex(RuntimeError, "does not match"):
            discover_neurochip_runtime_artifact(self.artifact_dir)

    def test_artifact_without_release_manifest_is_rejected(self) -> None:
        (self.artifact_dir / "artifact-manifest.json").unlink()

        with self.assertRaisesRegex(RuntimeError, "manifest is missing"):
            discover_neurochip_runtime_artifact(self.artifact_dir)

    def test_update_job_persists_and_deduplicates_completed_checksum(self) -> None:
        host = self._host()
        with mock.patch.object(
            self.state,
            "_provision_akida_host",
            return_value={
                "host": host,
                "installStatus": {
                    "packageVersion": "0.6.0",
                    "installMode": "systemd",
                },
            },
        ) as provision:
            created = self.state.create_akida_runtime_update_job(str(host["id"]))
            self.state._akida_runtime_update_threads[created["jobId"]].join(2)
            completed = self.state.get_akida_runtime_update_job(
                str(host["id"]), created["jobId"]
            )
            duplicate = self.state.create_akida_runtime_update_job(str(host["id"]))

        self.assertEqual(completed["status"], "completed")
        self.assertEqual(completed["installedVersion"], "0.6.0")
        self.assertEqual(duplicate["jobId"], completed["jobId"])
        self.assertEqual(provision.call_count, 1)
        persisted = json.loads(
            (
                self.repo_root / "nmtk" / "neuro_toolkit" / "launcher_settings.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(
            persisted["akidaRuntimeUpdateJobs"][0]["artifactSha256"],
            completed["artifactSha256"],
        )

    def test_update_job_redacts_internal_failure_and_records_recovery(self) -> None:
        host = self._host()
        secret = "private-host-stack-trace"
        with mock.patch.object(
            self.state,
            "_provision_akida_host",
            side_effect=RuntimeError(f"Connection refused while opening {secret}"),
        ):
            created = self.state.create_akida_runtime_update_job(str(host["id"]))
            self.state._akida_runtime_update_threads[created["jobId"]].join(2)
        failed = self.state.get_akida_runtime_update_job(
            str(host["id"]), created["jobId"]
        )

        self.assertEqual(failed["status"], "failed")
        self.assertEqual(failed["errorCode"], "ssh_unreachable")
        self.assertNotIn(secret, json.dumps(failed))
        self.assertIn("retry", failed["recovery"].lower())

    def _failed_job_for(self, **provision: object) -> dict[str, object]:
        host = self._host()
        with mock.patch.object(self.state, "_provision_akida_host", **provision):
            created = self.state.create_akida_runtime_update_job(str(host["id"]))
            self.state._akida_runtime_update_threads[created["jobId"]].join(2)
        return self.state.get_akida_runtime_update_job(
            str(host["id"]), created["jobId"]
        )

    def test_pip_resolution_failure_is_not_reported_as_a_version_mismatch(self) -> None:
        # pip writes "these package versions have conflicting dependencies",
        # which a substring match on "version" once turned into a retry-forever
        # version_mismatch. The conflict is deterministic; retrying cannot fix it.
        resolver_output = (
            "ERROR: Cannot install cnn2snn==2.19.1 and quantizeml==0.19.0 because "
            "these package versions have conflicting dependencies.\n"
            "ERROR: ResolutionImpossible: for help visit https://pip.pypa.io/"
        )
        failed = self._failed_job_for(side_effect=RuntimeError(resolver_output))

        self.assertEqual(failed["status"], "failed")
        self.assertEqual(failed["errorCode"], "dependency_conflict")
        self.assertNotIn("quantizeml", json.dumps(failed))
        self.assertIn("corrected akida package set", failed["recovery"].lower())

    def test_installed_version_difference_still_reports_version_mismatch(self) -> None:
        failed = self._failed_job_for(
            return_value={
                "host": {},
                "installStatus": {"packageVersion": "0.5.0", "installMode": "systemd"},
            }
        )

        self.assertEqual(failed["status"], "failed")
        self.assertEqual(failed["errorCode"], "version_mismatch")

    def test_absent_install_status_is_distinct_from_version_mismatch(self) -> None:
        failed = self._failed_job_for(return_value={"host": {}, "installStatus": None})

        self.assertEqual(failed["status"], "failed")
        self.assertEqual(failed["errorCode"], "install_status_missing")

    def test_missing_artifact_returns_typed_failed_job(self) -> None:
        host = self._host()
        (self.artifact_dir / "artifact-manifest.json").unlink()
        self.wheel_path.unlink()

        job = self.state.create_akida_runtime_update_job(str(host["id"]))

        self.assertEqual(job["status"], "failed")
        self.assertEqual(job["errorCode"], "artifact_missing")
        self.assertNotIn(str(self.artifact_dir), json.dumps(job))

    def test_provision_and_update_share_one_per_host_lock(self) -> None:
        host = self._host()
        entered = threading.Event()
        release = threading.Event()

        def blocked_install(*_args: object, **_kwargs: object) -> dict[str, object]:
            entered.set()
            release.wait(2)
            return {"host": host, "installStatus": {}}

        with mock.patch.object(
            self.state,
            "_provision_akida_host_unlocked",
            side_effect=blocked_install,
        ):
            first = threading.Thread(
                target=self.state.provision_akida_host,
                args=(str(host["id"]),),
            )
            first.start()
            self.assertTrue(entered.wait(1))
            concurrent = self.state.repair_akida_host(str(host["id"]))
            release.set()
            first.join(2)

        self.assertIn("already running", concurrent["error"])
