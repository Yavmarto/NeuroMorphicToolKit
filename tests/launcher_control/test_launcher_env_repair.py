"""Launcher control service tests: module environment repair (preflight repair, poetry/pip install sync, repair states)."""

from unittest import mock

from base import LauncherControlServiceTestBase

import nmtk.launcher_control.module_install as launcher_module_install
import nmtk.launcher_control.server as launcher_server


class TestLauncherEnvRepair(LauncherControlServiceTestBase):
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

    def test_preflight_accepts_recovered_poetry_probe_despite_stale_failed_fingerprint(
        self,
    ) -> None:
        self._write_poetry_pyproject()
        poetry_python = self.repo_root / "dummy_module" / ".venv" / "bin" / "python"
        poetry_python.parent.mkdir(parents=True, exist_ok=True)
        poetry_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        poetry_python.chmod(0o755)
        module = self.state._get_module("dummy")
        module["environmentFingerprint"] = "stale-fingerprint"
        module["preflightStatus"] = launcher_server.PREFLIGHT_FAILED
        module["preflightMessage"] = (
            "Missing required dependency: fastapi (needed by app.main)"
        )

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

    def test_cleanup_module_environment_removes_disposable_poetry_artifacts(
        self,
    ) -> None:
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
            mock.patch.object(
                launcher_module_install, "_poetry_command", return_value="poetry"
            ),
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
            mock.patch.object(
                launcher_module_install, "_poetry_command", return_value="poetry"
            ),
            mock.patch.object(
                launcher_server.subprocess,
                "run",
                return_value=mock.Mock(
                    returncode=0, stdout=str(poetry_python.parents[1]), stderr=""
                ),
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
            any(
                str(call[0]).endswith("/dummy_module/venv/bin/pip")
                for call in pip_calls
            )
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

    def test_repair_module_returns_installing_state_immediately(self) -> None:
        """repair_module() returns the module in 'installing' state immediately."""
        # Prevent the background thread from running so we see the initial state.
        with mock.patch.object(self.state, "_repair_sync", return_value=None):
            result = self.state.repair_module("dummy")

        self.assertEqual(result["status"], launcher_server.STATUS_INDEX["installing"])
        self.assertIsNone(result["healthStatus"])
        self.assertEqual(result["preflightStatus"], launcher_server.PREFLIGHT_OK)

    def test_repair_module_sets_installed_when_preflight_ok(self) -> None:
        """After a successful repair (preflight OK), module ends in 'installed' state."""
        # Put the module in error first.
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["error"]
        module["healthStatus"] = "import probe failed"

        ok_result = launcher_server.PreflightResult(
            status=launcher_server.PREFLIGHT_OK,
            message=None,
            capability_warnings=[],
            environment_fingerprint="abc123",
        )
        with mock.patch.object(self.state, "_preflight_module", return_value=ok_result):
            self.state.repair_module("dummy")
            task = self.state._tasks.get("dummy")
            if task:
                task.join(timeout=5.0)

        module = self.state._get_module("dummy")
        self.assertEqual(module["status"], launcher_server.STATUS_INDEX["installed"])
        self.assertIsNone(module["healthStatus"])

    def test_repair_module_sets_error_when_preflight_fails(self) -> None:
        """After a failed repair (preflight FAILED), module ends in 'error' state."""
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["error"]

        failed_result = launcher_server.PreflightResult(
            status=launcher_server.PREFLIGHT_FAILED,
            message="Cannot find required dependency: torch",
            capability_warnings=[],
            environment_fingerprint=None,
        )
        with mock.patch.object(
            self.state, "_preflight_module", return_value=failed_result
        ):
            self.state.repair_module("dummy")
            task = self.state._tasks.get("dummy")
            if task:
                task.join(timeout=5.0)

        module = self.state._get_module("dummy")
        self.assertEqual(module["status"], launcher_server.STATUS_INDEX["error"])
        self.assertEqual(
            module["healthStatus"], "Cannot find required dependency: torch"
        )

    def test_install_sync_cleans_venv_on_pip_failure(self) -> None:
        """When pip install fails, _install_sync removes the partial venv directory."""
        # Create a fake partial venv as if a previous install was interrupted.
        venv_path = self.repo_root / "dummy_module" / "venv"
        venv_path.mkdir(parents=True, exist_ok=True)
        (venv_path / "pyvenv.cfg").write_text("home = /usr/bin\n", encoding="utf-8")

        # Make _run_command raise to simulate a pip failure.
        call_count: dict[str, int] = {"n": 0}
        original_run_cmd = self.state._run_command

        def fail_on_pip(command: list, cwd: object, module_id: str) -> None:
            call_count["n"] += 1
            if "pip" in command or "install" in command:
                raise RuntimeError("pip install failed: network error")
            return original_run_cmd(command, cwd, module_id)  # type: ignore[return-value]

        with (
            mock.patch.object(self.state, "_run_command", side_effect=fail_on_pip),
            self.assertRaises(RuntimeError),
        ):
            self.state._install_sync("dummy")

        self.assertFalse(
            venv_path.exists(),
            "Partial venv directory must be removed after a failed pip install",
        )
