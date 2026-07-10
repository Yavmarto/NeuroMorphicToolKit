"""suite_api subprocess lifecycle: venv bootstrap, health probing, log streaming.

Imported by ``server.py`` right before ``LauncherControlState`` is defined, so
the ``from .server import ...`` below resolves against the partially
initialized module rather than re-entering it — the names it pulls in must
already be bound in ``server.py`` above that import line. Mirrors the
``PynqServiceMixin``/``AkidaServiceMixin`` extractions.
"""

from __future__ import annotations

import hashlib
import json
import os
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http import HTTPStatus
from pathlib import Path
from typing import Any

from .config import REPO_ROOT, SUITE_API_ENV_ROOT
from .preflight_types import PreflightResult
from .runtime_shared import _hash_file
from .server import (
    PREFLIGHT_FAILED,
    PREFLIGHT_OK,
    _default_user_data_dir,
    _resolved_lava_worker_url,
    _running_in_bundled_mode,
)

DEFAULT_SUITE_API_PORT = 9000
SUITE_API_STARTUP_TIMEOUT_SECONDS = 120.0
SUITE_API_STATUS_DISABLED = "disabled"
SUITE_API_STATUS_STARTING = "starting"
SUITE_API_STATUS_READY = "ready"
SUITE_API_STATUS_PREFLIGHT_FAILED = "preflight_failed"

_NEUROCNL_SUITE_API_EXTRAS = "training,studio,rockpool,synsense,norse"


def _suite_api_bind_host() -> str:
    return str(os.environ.get("NMTK_UVICORN_HOST") or "127.0.0.1").strip() or "127.0.0.1"


def _suite_api_base_url() -> str:
    return f"http://127.0.0.1:{DEFAULT_SUITE_API_PORT}"


def _suite_api_health_url() -> str:
    return f"{_suite_api_base_url()}/api/suite/health"


def _suite_api_env_dir() -> Path:
    explicit = str(os.environ.get("NMTK_SUITE_API_ENV_DIR") or "").strip()
    if explicit:
        return Path(explicit).expanduser()
    if _running_in_bundled_mode():
        return _default_user_data_dir() / "suite_api_env"
    return SUITE_API_ENV_ROOT


def _suite_api_env_python(env_dir: Path) -> Path:
    if os.name == "nt":
        return env_dir / "venv" / "Scripts" / "python.exe"
    return env_dir / "venv" / "bin" / "python"


def _suite_api_env_stamp(env_dir: Path) -> Path:
    return env_dir / "install-fingerprint.json"


def _suite_api_dev_install_paths() -> tuple[Path, ...]:
    return (
        REPO_ROOT / "suite_api",
        REPO_ROOT / "neurocnl",
        REPO_ROOT / "Neuro-Dream-Hand",
        REPO_ROOT / "Neurohub",
        REPO_ROOT / "Neurochip",
        REPO_ROOT / "Neurobench" / "neurobench",
        REPO_ROOT / "Neurosense",
    )


def _suite_api_install_target(install_path: Path) -> str:
    if install_path.name == "neurocnl":
        return f"{install_path}[{_NEUROCNL_SUITE_API_EXTRAS}]"
    return str(install_path)


def _suite_api_env_fingerprint_files() -> tuple[Path, ...]:
    return (
        REPO_ROOT / "suite_api" / "pyproject.toml",
        REPO_ROOT / "neurocnl" / "pyproject.toml",
        REPO_ROOT / "Neuro-Dream-Hand" / "pyproject.toml",
        REPO_ROOT / "Neurohub" / "pyproject.toml",
        REPO_ROOT / "Neurochip" / "pyproject.toml",
        REPO_ROOT / "Neurobench" / "neurobench" / "pyproject.toml",
        REPO_ROOT / "Neurosense" / "pyproject.toml",
    )


def _suite_api_env_fingerprint() -> str:
    payload = {
        str(path.relative_to(REPO_ROOT)): _hash_file(path)
        for path in _suite_api_env_fingerprint_files()
        if path.exists()
    }
    return hashlib.sha256(
        json.dumps(payload, sort_keys=True).encode("utf-8")
    ).hexdigest()


def _suite_api_pythonpath_entries() -> list[str]:
    entries = [
        str(REPO_ROOT),
        str(REPO_ROOT / "Neurohub"),
        str(REPO_ROOT / "Neurosense"),
        str(REPO_ROOT / "Neurochip"),
        str(REPO_ROOT / "Neurobench" / "neurobench"),
    ]
    return [entry for entry in entries if Path(entry).exists()]


def _suite_api_pythonpath() -> str:
    entries = _suite_api_pythonpath_entries()
    existing = str(os.environ.get("PYTHONPATH") or "").strip()
    if existing:
        entries.append(existing)
    return os.pathsep.join(entries)


def _suite_api_env_is_bootstrapped(venv_python: Path) -> bool:
    if not venv_python.exists():
        return False

    result = subprocess.run(
        [
            str(venv_python),
            "-c",
            "import fastapi, uvicorn, suite_api.main",
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
        env={**os.environ, "PYTHONPATH": _suite_api_pythonpath()},
    )
    return result.returncode == 0


def _suite_api_health_probe() -> tuple[bool, str | None]:
    try:
        with urllib.request.urlopen(_suite_api_health_url(), timeout=2.0) as response:
            body = response.read().decode("utf-8", errors="replace")
            if int(response.status) == HTTPStatus.OK:
                return True, body
            return False, body or f"Unexpected status {response.status}"
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return False, body or f"HTTP {exc.code}"
    except (urllib.error.URLError, TimeoutError, socket.timeout) as exc:
        return False, str(exc)


class SuiteApiServiceMixin:
    def _set_suite_api_state(self, status: str, message: str | None = None) -> None:
        with self._lock:
            self._suite_api_status = status
            self._suite_api_message = message

    def _suite_api_ready_result(self) -> PreflightResult:
        if not self._manage_suite_api:
            return PreflightResult(status=PREFLIGHT_OK)
        if self._suite_api_status == SUITE_API_STATUS_READY:
            return PreflightResult(status=PREFLIGHT_OK, message="Managed by suite_api")
        if self._suite_api_status == SUITE_API_STATUS_STARTING:
            return PreflightResult(
                status=PREFLIGHT_FAILED,
                message=self._suite_api_message
                or "suite_api is still starting; wait for the control plane to finish booting",
            )
        return PreflightResult(
            status=PREFLIGHT_FAILED,
            message=self._suite_api_message or "suite_api is unavailable",
        )

    def _suite_api_python(self) -> str:
        if _running_in_bundled_mode():
            return sys.executable

        env_dir = _suite_api_env_dir()
        venv_dir = env_dir / "venv"
        venv_python = _suite_api_env_python(env_dir)
        fingerprint = _suite_api_env_fingerprint()
        stamp_path = _suite_api_env_stamp(env_dir)
        saved_fingerprint = ""
        if stamp_path.exists():
            try:
                saved_fingerprint = str(
                    json.loads(stamp_path.read_text(encoding="utf-8")).get("fingerprint")
                    or ""
                )
            except (json.JSONDecodeError, OSError):
                saved_fingerprint = ""

        env_dir.mkdir(parents=True, exist_ok=True)
        venv_created = False
        if not venv_python.exists():
            result = subprocess.run(
                [sys.executable, "-m", "venv", str(venv_dir)],
                cwd=REPO_ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                raise RuntimeError(
                    result.stderr.strip()
                    or result.stdout.strip()
                    or "Failed to create suite_api virtual environment"
                )
            venv_created = True

        needs_install = venv_created or saved_fingerprint != fingerprint
        if not needs_install and not _suite_api_env_is_bootstrapped(venv_python):
            needs_install = True

        if needs_install:
            for install_path in _suite_api_dev_install_paths():
                if not install_path.exists():
                    raise RuntimeError(
                        f"suite_api dependency checkout not found: {install_path}"
                    )
                install_target = _suite_api_install_target(install_path)
                result = subprocess.run(
                    [str(venv_python), "-m", "pip", "install", "-e", install_target],
                    cwd=REPO_ROOT,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                if result.returncode != 0:
                    raise RuntimeError(
                        result.stderr.strip()
                        or result.stdout.strip()
                        or f"Failed to install {install_path}"
                    )
            stamp_path.write_text(
                json.dumps({"fingerprint": fingerprint}, indent=2, sort_keys=True),
                encoding="utf-8",
            )

        return str(venv_python)

    def _suite_api_environment(self) -> dict[str, str]:
        environment = dict(os.environ)
        environment["PYTHONPATH"] = _suite_api_pythonpath()
        lava_url = _resolved_lava_worker_url()
        if lava_url:
            environment["NEUROCNL_LAVA_WORKER_URL"] = lava_url
        return environment

    def _stream_suite_api_logs(self, process: subprocess.Popen[str]) -> None:
        if process.stdout is None:
            return

        def _pump() -> None:
            assert process.stdout is not None
            for line in process.stdout:
                message = line.rstrip()
                if not message:
                    continue
                self._suite_api_logs.append(message)
                with self._terminal_lock:
                    print(f"[suite_api] {message}")

        threading.Thread(
            target=_pump,
            name="suite-api-stdout",
            daemon=True,
        ).start()

    def _ensure_suite_api_ready(self) -> None:
        if not self._manage_suite_api or self._shutdown.is_set():
            return

        ok, _message = _suite_api_health_probe()
        if ok:
            self._set_suite_api_state(SUITE_API_STATUS_READY, "Managed by suite_api")
            return

        self._set_suite_api_state(
            SUITE_API_STATUS_STARTING,
            "Starting suite_api and provisioning its runtime environment",
        )
        try:
            python_path = self._suite_api_python()
        except RuntimeError as exc:
            self._set_suite_api_state(SUITE_API_STATUS_PREFLIGHT_FAILED, str(exc))
            return

        process = subprocess.Popen(
            [
                python_path,
                "-m",
                "uvicorn",
                "suite_api.main:app",
                "--host",
                _suite_api_bind_host(),
                "--port",
                str(DEFAULT_SUITE_API_PORT),
                "--log-level",
                str(self._settings["logLevel"]),
            ],
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            text=True,
            bufsize=1,
            env=self._suite_api_environment(),
        )
        self._suite_api_process = process
        self._stream_suite_api_logs(process)

        deadline = time.monotonic() + SUITE_API_STARTUP_TIMEOUT_SECONDS
        while time.monotonic() < deadline and not self._shutdown.is_set():
            ok, message = _suite_api_health_probe()
            if ok:
                self._set_suite_api_state(SUITE_API_STATUS_READY, "Managed by suite_api")
                return
            if process.poll() is not None:
                startup_logs = "\n".join(self._suite_api_logs).strip()
                self._set_suite_api_state(
                    SUITE_API_STATUS_PREFLIGHT_FAILED,
                    startup_logs or message or f"suite_api exited with code {process.returncode}",
                )
                return
            time.sleep(0.5)

        self._set_suite_api_state(
            SUITE_API_STATUS_PREFLIGHT_FAILED,
            f"Timed out waiting for suite_api health at {_suite_api_health_url()}",
        )
