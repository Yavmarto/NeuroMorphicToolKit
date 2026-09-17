"""Module install/update/repair workers, preflight, and Akida preparation."""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .config import REPO_ROOT
from .module_environment import (
    _candidate_environment_files,
    _current_platform_key,
    _missing_python_message,
    _module_install_dir,
    _module_install_extras,
    _module_install_strategy,
    _module_optional_imports,
    _module_python_path,
    _module_required_imports,
    _module_run_dir,
    _module_start_strategy,
    _module_uses_poetry,
    _module_venv_python,
    _normalize_akida_runtime_config,
    _poetry_command,
    _poetry_fallback_env_root,
    _version_matches_range,
)
from .preflight_types import PreflightResult
from .process_supervision import _dedupe_messages, _message_from_probe_outcome
from .runtime_shared import _hash_file
from .state_contracts import (
    IMPORT_PROBE_SCRIPT,
    PREFLIGHT_DEGRADED,
    PREFLIGHT_FAILED,
    PREFLIGHT_OK,
    PREFLIGHT_SENTINEL,
    STATUS_INDEX,
    SUPPORTED_INSTALL_STRATEGIES,
)


class ModuleInstallMixin:
    def prepare_akida_runtime(self, module_id: str) -> dict[str, Any]:
        module = self._get_module(module_id)
        runtime = _normalize_akida_runtime_config(module.get("akidaRuntime"))
        if runtime is None:
            raise RuntimeError(
                f"Module '{module_id}' does not define an Akida runtime profile"
            )

        preflight = self._preflight_module(module, allow_repair=False)
        self._update_module_fields(module_id, **preflight.state_fields())
        if preflight.status == PREFLIGHT_FAILED:
            self._update_module_fields(
                module_id,
                akidaRuntimeState={
                    "status": "error",
                    "message": preflight.message or "Module preflight failed",
                    "preparedAt": None,
                },
            )
            return self.serialize_module(module_id)

        platform_key = _current_platform_key()
        if platform_key not in runtime["supportedPlatforms"]:
            self._update_module_fields(
                module_id,
                akidaRuntimeState={
                    "status": "unsupported_host",
                    "message": (
                        "Local Akida SDK install is not supported on this host. "
                        "Use the local simulator and a Linux or Windows Neurochip "
                        "host for SDK verification."
                    ),
                    "preparedAt": None,
                },
            )
            return self.serialize_module(module_id)

        install_dir = _module_install_dir(module)
        python_path = _module_python_path(module)
        python_version_result = self._run_command(
            [
                str(python_path),
                "-c",
                'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")',
            ],
            cwd=install_dir,
            module_id=module_id,
        )
        python_version = str(python_version_result.stdout or "").strip()
        if not _version_matches_range(python_version, runtime["pythonRange"]):
            self._update_module_fields(
                module_id,
                akidaRuntimeState={
                    "status": "unsupported_python",
                    "message": (
                        "Akida SDK installation requires Python "
                        f"{runtime['pythonRange']}; current module env is "
                        f"{python_version or 'unknown'}. Keep scaffold export "
                        "local, then verify through a Linux or Windows "
                        "Neurochip host running Python 3.10-3.12."
                    ),
                    "preparedAt": None,
                },
            )
            return self.serialize_module(module_id)

        self._update_module_fields(
            module_id,
            akidaRuntimeState={
                "status": "preparing",
                "message": "Installing Akida runtime dependencies...",
                "preparedAt": None,
            },
        )

        if _module_uses_poetry(module) and (poetry := _poetry_command()) is not None:
            command = [
                poetry,
                "run",
                "python",
                "-m",
                "pip",
                "install",
                *runtime["requiredPackages"],
            ]
        else:
            command = [
                str(python_path),
                "-m",
                "pip",
                "install",
                *runtime["requiredPackages"],
            ]
        self._run_command(command, cwd=install_dir, module_id=module_id)

        self._update_module_fields(
            module_id,
            akidaRuntimeState={
                "status": "ready",
                "message": "Akida runtime is prepared for local SDK verification.",
                "preparedAt": datetime.now(timezone.utc).isoformat(),
            },
        )
        return self.serialize_module(module_id)

    def _module_python_version(self, python_path: Path) -> str:
        result = subprocess.run(
            [str(python_path), "--version"],
            capture_output=True,
            text=True,
            check=False,
        )
        version = (result.stdout or result.stderr).strip()
        if result.returncode != 0 or not version:
            raise RuntimeError(
                result.stderr.strip()
                or f"Failed to inspect Python version at {python_path}"
            )
        return version

    def _compute_environment_fingerprint(self, module: dict[str, Any]) -> str:
        python_path = _module_python_path(module)
        if not python_path.exists():
            raise RuntimeError(_missing_python_message(module, python_path))

        payload = {
            "pythonVersion": self._module_python_version(python_path),
            "pythonPath": str(python_path),
            "installDir": str(_module_install_dir(module)),
            "runDir": str(_module_run_dir(module)),
            "installStrategy": _module_install_strategy(module),
            "installExtras": _module_install_extras(module),
            "startStrategy": _module_start_strategy(module),
            "uvicornTarget": str(module.get("uvicornTarget", "")),
            "files": {
                str(path.relative_to(REPO_ROOT)): _hash_file(path)
                for path in _candidate_environment_files(module)
            },
        }
        return hashlib.sha256(
            json.dumps(payload, sort_keys=True).encode("utf-8")
        ).hexdigest()

    def _cleanup_module_environment(self, module_id: str) -> None:
        with self._lock:
            module = dict(self._get_module(module_id))

        install_dir = _module_install_dir(module)
        for venv_name in (".venv", "venv"):
            venv_path = install_dir / venv_name
            if venv_path.exists():
                shutil.rmtree(venv_path, ignore_errors=True)

        if not _module_uses_poetry(module):
            return

        poetry_toml = install_dir / "poetry.toml"
        if poetry_toml.exists():
            try:
                poetry_toml.unlink()
            except OSError:
                pass

        fallback_env_root = _poetry_fallback_env_root(module)
        if fallback_env_root.exists():
            shutil.rmtree(fallback_env_root, ignore_errors=True)

        poetry = _poetry_command()
        if poetry is None:
            return

        try:
            subprocess.run(
                [poetry, "env", "remove", "--all"],
                cwd=install_dir,
                capture_output=True,
                text=True,
                check=False,
            )
        except Exception:  # noqa: BLE001, S110 - cleanup is best-effort
            pass

    def _run_import_probe(self, module: dict[str, Any]) -> PreflightResult:
        python_path = _module_python_path(module)
        if not python_path.exists():
            return PreflightResult(
                status=PREFLIGHT_FAILED,
                message=_missing_python_message(module, python_path),
            )

        required_imports = _module_required_imports(module)
        optional_imports = _module_optional_imports(module)
        result = subprocess.run(
            [
                str(python_path),
                "-c",
                IMPORT_PROBE_SCRIPT,
                json.dumps(required_imports),
                json.dumps(optional_imports),
            ],
            cwd=_module_run_dir(module),
            capture_output=True,
            text=True,
            check=False,
        )
        if result.stderr:
            self._append_log(
                module["id"], result.stderr, stderr=True, emit_terminal=True
            )
        if result.stdout:
            for line in result.stdout.splitlines():
                if not line.startswith(PREFLIGHT_SENTINEL):
                    self._append_log(module["id"], line, emit_terminal=True)

        sentinel_line = next(
            (
                line
                for line in result.stdout.splitlines()
                if line.startswith(PREFLIGHT_SENTINEL)
            ),
            "",
        )
        if result.returncode != 0 or not sentinel_line:
            return PreflightResult(
                status=PREFLIGHT_FAILED,
                message=(
                    result.stderr.strip()
                    or result.stdout.strip()
                    or "Preflight import probe failed"
                ),
            )

        payload = json.loads(sentinel_line.removeprefix(PREFLIGHT_SENTINEL))
        required_failures = [
            outcome for outcome in payload.get("required", []) if not outcome.get("ok")
        ]
        capability_warnings = _dedupe_messages(
            [
                _message_from_probe_outcome(outcome, optional=True)
                for outcome in payload.get("optional", [])
                if not outcome.get("ok")
            ]
        )

        if required_failures:
            failure_messages = _dedupe_messages(
                [
                    _message_from_probe_outcome(outcome, optional=False)
                    for outcome in required_failures
                ]
            )
            return PreflightResult(
                status=PREFLIGHT_FAILED,
                message="; ".join(failure_messages),
                capability_warnings=capability_warnings,
            )

        if capability_warnings:
            return PreflightResult(
                status=PREFLIGHT_DEGRADED,
                message=capability_warnings[0],
                capability_warnings=capability_warnings,
            )

        return PreflightResult(status=PREFLIGHT_OK)

    def _preflight_module(
        self, module: dict[str, Any], *, allow_repair: bool
    ) -> PreflightResult:
        module_id = str(module["id"])
        install_dir = _module_install_dir(module)
        run_dir = _module_run_dir(module)

        if not install_dir.exists():
            return PreflightResult(
                status=PREFLIGHT_FAILED,
                message=f"Module directory not found: {install_dir}",
            )
        if not run_dir.exists():
            return PreflightResult(
                status=PREFLIGHT_FAILED,
                message=f"Run directory not found: {run_dir}",
            )

        python_path = _module_python_path(module)
        if not python_path.exists():
            if not allow_repair:
                return PreflightResult(
                    status=PREFLIGHT_FAILED,
                    message=_missing_python_message(module, python_path),
                )
            if _module_uses_poetry(module):
                self._cleanup_module_environment(module_id)
            self._install_sync(module_id)
            module = self._get_module(module_id)
            python_path = _module_python_path(module)

        fingerprint = self._compute_environment_fingerprint(module)
        saved_fingerprint = str(module.get("environmentFingerprint") or "").strip()
        if saved_fingerprint and saved_fingerprint != fingerprint:
            if (
                _module_uses_poetry(module)
                and str(module.get("preflightStatus", PREFLIGHT_OK)) == PREFLIGHT_FAILED
            ):
                recovered_result = self._run_import_probe(module)
                recovered_result.environment_fingerprint = fingerprint
                if recovered_result.status != PREFLIGHT_FAILED:
                    return recovered_result
            message = (
                "Environment fingerprint changed; reinstall required before launch"
            )
            if not allow_repair:
                return PreflightResult(
                    status=PREFLIGHT_FAILED,
                    message=message,
                    environment_fingerprint=fingerprint,
                )
            self._append_log(module_id, message, emit_terminal=True)
            if _module_uses_poetry(module):
                self._cleanup_module_environment(module_id)
            self._install_sync(module_id)
            module = self._get_module(module_id)
            fingerprint = self._compute_environment_fingerprint(module)

        probe_result = self._run_import_probe(module)
        probe_result.environment_fingerprint = fingerprint
        if probe_result.status != PREFLIGHT_FAILED or not allow_repair:
            return probe_result

        if _module_uses_poetry(module):
            self._append_log(
                module_id,
                "Preflight failed; cleaning and reinstalling once to repair the module environment",
                emit_terminal=True,
            )
            self._cleanup_module_environment(module_id)
        else:
            self._append_log(
                module_id,
                "Preflight failed; reinstalling once to repair the module environment",
                emit_terminal=True,
            )
        self._install_sync(module_id)
        module = self._get_module(module_id)
        repaired_result = self._run_import_probe(module)
        repaired_result.environment_fingerprint = self._compute_environment_fingerprint(
            module
        )
        return repaired_result

    def _install_sync(self, module_id: str) -> None:
        module = self._get_module(module_id)
        install_dir = _module_install_dir(module)
        if not install_dir.exists():
            raise RuntimeError(f"Module directory not found: {install_dir}")

        install_strategy = _module_install_strategy(module)
        if install_strategy not in SUPPORTED_INSTALL_STRATEGIES:
            raise RuntimeError(
                f"Unsupported install strategy '{install_strategy}' for {module_id}"
            )

        venv_python = _module_venv_python(module)
        poetry = _poetry_command()
        use_poetry = _module_uses_poetry(module) and poetry is not None

        self._update_module_fields(
            module_id, status=STATUS_INDEX["installing"], installProgress=0.1
        )
        if poetry is not None and _module_uses_poetry(module):
            # Configure Poetry before any `poetry run ...` command so repairs
            # consistently recreate an in-project `.venv`.
            self._run_command(
                [str(poetry), "config", "virtualenvs.in-project", "true", "--local"],
                cwd=install_dir,
                module_id=module_id,
            )
        if not use_poetry and not venv_python.exists():
            self._run_command(
                [sys.executable, "-m", "venv", "venv"],
                cwd=install_dir,
                module_id=module_id,
            )
            venv_python = _module_venv_python(module)
        if not use_poetry:
            self._ensure_module_pip(venv_python, install_dir, module_id)

        self._update_module_fields(module_id, installProgress=0.3)
        for dependency in module.get("localDeps", []):
            dep_path = (REPO_ROOT / dependency).resolve()
            if dep_path.exists():
                if poetry is not None and _module_uses_poetry(module):
                    self._run_command(
                        [
                            str(poetry),
                            "run",
                            "python",
                            "-m",
                            "pip",
                            "install",
                            str(dep_path),
                        ],
                        cwd=install_dir,
                        module_id=module_id,
                    )
                else:
                    self._run_command(
                        [str(venv_python), "-m", "pip", "install", str(dep_path)],
                        cwd=install_dir,
                        module_id=module_id,
                    )

        self._update_module_fields(module_id, installProgress=0.6)
        try:
            if poetry is not None and _module_uses_poetry(module):
                self._run_command(
                    [str(poetry), "lock"],
                    cwd=install_dir,
                    module_id=module_id,
                )
                self._run_command(
                    [str(poetry), "install", "--no-interaction", "--no-root"],
                    cwd=install_dir,
                    module_id=module_id,
                )
            else:
                install_extras = _module_install_extras(module)
                install_target = (
                    f".[{','.join(install_extras)}]" if install_extras else "."
                )
                self._run_command(
                    [str(venv_python), "-m", "pip", "install", install_target],
                    cwd=install_dir,
                    module_id=module_id,
                )
            environment_fingerprint = self._compute_environment_fingerprint(module)
            self._update_module_fields(
                module_id,
                status=STATUS_INDEX["installed"],
                installProgress=1.0,
                healthStatus=None,
                preflightStatus=PREFLIGHT_OK,
                preflightMessage=None,
                capabilityWarnings=[],
                environmentFingerprint=environment_fingerprint,
            )
        except Exception:
            # Rollback: remove any partial venv so the next install starts clean.
            self._append_log(
                module_id,
                "Installation failed — removing partial environment so the next install starts fresh.",
                stderr=True,
                emit_terminal=True,
            )
            self._cleanup_module_environment(module_id)
            raise

    def _ensure_module_pip(self, python_path: Path, cwd: Path, module_id: str) -> None:
        probe = subprocess.run(
            [str(python_path), "-m", "pip", "--version"],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
        if probe.returncode == 0:
            return

        self._append_log(
            module_id,
            "pip is missing from the module environment; bootstrapping it now",
            emit_terminal=True,
        )
        ensurepip = subprocess.run(
            [str(python_path), "-m", "ensurepip", "--upgrade"],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
        if ensurepip.stdout:
            self._append_log(module_id, ensurepip.stdout, emit_terminal=True)
        if ensurepip.stderr:
            self._append_log(
                module_id, ensurepip.stderr, stderr=True, emit_terminal=True
            )
        if ensurepip.returncode != 0:
            self._append_log(
                module_id,
                "ensurepip unavailable; downloading get-pip.py as a fallback",
                emit_terminal=True,
            )
            with tempfile.NamedTemporaryFile(
                mode="w", suffix="-get-pip.py", delete=False, dir=cwd
            ) as handle:
                temp_path = Path(handle.name)
            try:
                urllib.request.urlretrieve(
                    "https://bootstrap.pypa.io/get-pip.py",
                    temp_path,
                )
                self._run_command(
                    [str(python_path), str(temp_path)],
                    cwd=cwd,
                    module_id=module_id,
                )
            finally:
                try:
                    temp_path.unlink(missing_ok=True)
                except OSError:
                    pass

        final_probe = subprocess.run(
            [str(python_path), "-m", "pip", "--version"],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
        if final_probe.returncode != 0:
            raise RuntimeError(
                final_probe.stderr.strip()
                or "pip bootstrap failed for the module environment"
            )

    def _prune_docker_build_cache(self, keep_storage: str = "20GB") -> None:
        """Prune the local Docker BuildKit cache before any docker compose build.

        Accumulated stale cache layers (especially from builds interrupted by
        disk-full conditions) can corrupt the image store with invalid tar
        headers on the next build.  Pruning with --keep-storage retains
        recently-used layers so incremental builds remain fast while evicting
        old cruft.

        Call this immediately before any ``docker compose up --build`` or
        ``docker build`` invocation.  When auto-update eventually triggers
        Docker rebuilds from within the launcher, add the call here.
        """
        if shutil.which("docker") is None:
            return
        try:
            subprocess.run(
                ["docker", "builder", "prune", "-f", f"--keep-storage={keep_storage}"],
                check=False,
                timeout=120,
            )
        except Exception:  # noqa: BLE001, S110 - non-fatal: build proceeds regardless
            pass  # Non-fatal: build proceeds regardless; worst case is a stale cache

    def _update_sync(self, module_id: str) -> None:
        module = self._get_module(module_id)
        self.stop_module(module_id)
        self._update_module_fields(
            module_id,
            status=STATUS_INDEX["updating"],
            installProgress=0.2,
            healthStatus=None,
        )
        self._install_sync(module_id)
        with self._lock:
            remote_version = module.get("remoteVersion")
            if isinstance(remote_version, str) and remote_version:
                module["version"] = remote_version
                module["remoteVersion"] = remote_version
                self._persist_states()

    def _repair_sync(self, module_id: str) -> None:
        """Background worker for repair_module().

        Runs _preflight_module with allow_repair=True.  Unlike _start_sync,
        does not attempt to start the service after a successful repair.
        """
        with self._lock:
            module = dict(self._get_module(module_id))

        preflight = self._preflight_module(module, allow_repair=True)
        self._update_module_fields(module_id, **preflight.state_fields())

        if preflight.status == PREFLIGHT_FAILED:
            self._update_module_fields(
                module_id,
                status=STATUS_INDEX["error"],
                healthStatus=preflight.message,
            )
            raise RuntimeError(preflight.message or "Module repair failed")

        next_status = (
            STATUS_INDEX["degraded"]
            if preflight.status == PREFLIGHT_DEGRADED
            else STATUS_INDEX["installed"]
        )
        self._update_module_fields(
            module_id,
            status=next_status,
            healthStatus=preflight.message
            if preflight.status == PREFLIGHT_DEGRADED
            else None,
        )
