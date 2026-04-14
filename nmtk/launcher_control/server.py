"""Host-side launcher control service for desktop and web launcher clients."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
import tomllib
import textwrap
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlparse


STATUS_INDEX: dict[str, int] = {
    "notInstalled": 0,
    "installing": 1,
    "installed": 2,
    "starting": 3,
    "running": 4,
    "stopping": 5,
    "error": 6,
    "degraded": 7,
    "updating": 8,
}

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULES_MANIFEST = REPO_ROOT / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
REMOTE_MANIFEST = (
    REPO_ROOT / "nmtk" / "neuro_toolkit" / "assets" / "remote_modules.json"
)
STATE_FILE = REPO_ROOT / "nmtk" / "neuro_toolkit" / "module_states.json"
SETTINGS_FILE = REPO_ROOT / "nmtk" / "neuro_toolkit" / "launcher_settings.json"

DEFAULT_CONTROL_LOG_LEVEL = "info"
HEALTH_POLL_SECONDS = 5.0
STARTUP_GRACE_SECONDS = 12.0
LOG_LINE_LIMIT = 400
PREFLIGHT_OK = "ok"
PREFLIGHT_DEGRADED = "degraded"
PREFLIGHT_FAILED = "failed"
SUPPORTED_INSTALL_STRATEGIES = {"pip"}
SUPPORTED_START_STRATEGIES = {"uvicorn", "none"}
PREFLIGHT_SENTINEL = "NMTK_PREFLIGHT_JSON="
IMPORT_PROBE_SCRIPT = textwrap.dedent(
    f"""
    import importlib
    import json
    import sys

    required = json.loads(sys.argv[1])
    optional = json.loads(sys.argv[2])
    results = {{"required": [], "optional": []}}

    for bucket, imports in (("required", required), ("optional", optional)):
        for name in imports:
            outcome = {{"import": name, "ok": True}}
            try:
                importlib.import_module(name)
            except ModuleNotFoundError as exc:
                outcome = {{
                    "import": name,
                    "ok": False,
                    "kind": "missing",
                    "missing": exc.name,
                }}
            except Exception as exc:  # noqa: BLE001
                outcome = {{
                    "import": name,
                    "ok": False,
                    "kind": "error",
                    "error": f"{{type(exc).__name__}}: {{exc}}",
                }}
            results[bucket].append(outcome)

    print("{PREFLIGHT_SENTINEL}" + json.dumps(results, sort_keys=True))
    """
).strip()


def _read_json_file(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return default


def _write_json_file(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def _status_name(index: int) -> str:
    for name, value in STATUS_INDEX.items():
        if value == index:
            return name
    return "notInstalled"


def _module_root(module: dict[str, Any]) -> Path:
    install_path = module.get("installPath") or module.get("directory") or ""
    return (REPO_ROOT / install_path).resolve()


def _module_install_dir(module: dict[str, Any]) -> Path:
    source_path = module.get("sourcePath") or "."
    return (_module_root(module) / source_path).resolve()


def _module_run_dir(module: dict[str, Any]) -> Path:
    run_path = module.get("runPath") or module.get("sourcePath") or "."
    return (_module_root(module) / run_path).resolve()


def _module_venv_python(module: dict[str, Any]) -> Path:
    """Return the python path, checking .venv (poetry in-project) before venv."""
    install_dir = _module_install_dir(module)
    if os.name == "nt":
        dotenv = install_dir / ".venv" / "Scripts" / "python.exe"
        return dotenv if dotenv.exists() else install_dir / "venv" / "Scripts" / "python.exe"
    dotenv = install_dir / ".venv" / "bin" / "python"
    return dotenv if dotenv.exists() else install_dir / "venv" / "bin" / "python"


def _module_venv_pip(module: dict[str, Any]) -> Path:
    install_dir = _module_install_dir(module)
    if os.name == "nt":
        dotenv = install_dir / ".venv" / "Scripts" / "pip.exe"
        return dotenv if dotenv.exists() else install_dir / "venv" / "Scripts" / "pip.exe"
    dotenv = install_dir / ".venv" / "bin" / "pip"
    return dotenv if dotenv.exists() else install_dir / "venv" / "bin" / "pip"


def _module_pyproject_path(module: dict[str, Any]) -> Path | None:
    install_dir = _module_install_dir(module)
    module_root = _module_root(module)
    for candidate in (
        install_dir / "pyproject.toml",
        module_root / "pyproject.toml",
    ):
        if candidate.exists():
            return candidate
    return None


def _module_uses_poetry(module: dict[str, Any]) -> bool:
    pyproject_path = _module_pyproject_path(module)
    if pyproject_path is None:
        return False

    try:
        pyproject = tomllib.loads(pyproject_path.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError):
        return False

    build_backend = str(pyproject.get("build-system", {}).get("build-backend", "")).strip()
    tool_table = pyproject.get("tool", {})
    return build_backend == "poetry.core.masonry.api" or "poetry" in tool_table


def _poetry_fallback_env_root(module: dict[str, Any]) -> Path:
    module_id = str(module.get("id") or "").strip()
    return REPO_ROOT / ".poetry-envs" / module_id


def _poetry_command() -> str | None:
    found = shutil.which("poetry")
    if found:
        return found
    # Poetry is commonly installed outside the system PATH.
    # Probe well-known locations so the control service works even when
    # launched by Flutter (which inherits a minimal environment).
    candidates = [
        Path.home() / ".local" / "bin" / "poetry",
        Path.home() / ".poetry" / "bin" / "poetry",
        # pipx default bin dir
        Path.home() / ".local" / "pipx" / "venvs" / "poetry" / "bin" / "poetry",
    ]
    for candidate in candidates:
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def _poetry_env_python(module: dict[str, Any]) -> Path | None:
    if not _module_uses_poetry(module):
        return None

    install_dir = _module_install_dir(module)

    # Check in-project .venv first (set by poetry config virtualenvs.in-project true).
    # This is the most reliable path and requires no subprocess call.
    if os.name == "nt":
        inproject_python = install_dir / ".venv" / "Scripts" / "python.exe"
    else:
        inproject_python = install_dir / ".venv" / "bin" / "python"
    if inproject_python.exists():
        return inproject_python

    fallback_env_root = _poetry_fallback_env_root(module)
    if os.name == "nt":
        fallback_python = fallback_env_root / "Scripts" / "python.exe"
    else:
        fallback_python = fallback_env_root / "bin" / "python"
    if fallback_python.exists():
        return fallback_python

    poetry = _poetry_command()
    if poetry is None:
        return None

    result = subprocess.run(
        [poetry, "env", "info", "--path"],
        cwd=install_dir,
        capture_output=True,
        text=True,
        check=False,
    )
    env_path = Path((result.stdout or "").strip())
    if result.returncode != 0 or not env_path:
        return None

    if os.name == "nt":
        python_path = env_path / "Scripts" / "python.exe"
    else:
        python_path = env_path / "bin" / "python"
    return python_path if python_path.exists() else None


def _module_python_path(module: dict[str, Any]) -> Path:
    return _poetry_env_python(module) or _module_venv_python(module)


def _missing_python_message(module: dict[str, Any], python_path: Path) -> str:
    if _module_uses_poetry(module):
        return f"Module python missing at {python_path}"
    return f"Virtualenv python missing at {python_path}"


def _effective_port(module: dict[str, Any]) -> int | None:
    custom = module.get("customPort")
    if isinstance(custom, int):
        return custom
    port = module.get("port")
    return port if isinstance(port, int) else None


def _uvicorn_host() -> str:
    host = os.environ.get("NMTK_UVICORN_HOST", "127.0.0.1").strip()
    return host or "127.0.0.1"


def _mujoco_available() -> bool:
    return any(
        (REPO_ROOT / candidate).exists()
        for candidate in (
            ".mujoco",
            "mujoco",
        )
    ) or any(
        os.path.exists(candidate)
        for candidate in (
            os.path.expanduser("~/.mujoco"),
            "/Applications/MuJoCo.app",
        )
    )


def _module_install_strategy(module: dict[str, Any]) -> str:
    strategy = str(module.get("installStrategy", "pip")).strip().lower()
    return strategy or "pip"


def _module_start_strategy(module: dict[str, Any]) -> str:
    if not module.get("uvicornTarget"):
        return "none"
    strategy = str(module.get("startStrategy", "uvicorn")).strip().lower()
    return strategy or "uvicorn"


def _normalized_import_list(raw: Any) -> list[str]:
    if not isinstance(raw, list):
        return []
    imports: list[str] = []
    for item in raw:
        if isinstance(item, str):
            value = item.strip()
            if value:
                imports.append(value)
    return imports


def _module_required_imports(module: dict[str, Any]) -> list[str]:
    imports = _normalized_import_list(module.get("requiredImports"))
    uvicorn_target = str(module.get("uvicornTarget", "")).strip()
    app_module = uvicorn_target.split(":", 1)[0] if uvicorn_target else ""
    if app_module and app_module not in imports:
        imports.append(app_module)
    return imports


def _module_optional_imports(module: dict[str, Any]) -> list[str]:
    return _normalized_import_list(module.get("optionalImports"))


def _candidate_environment_files(module: dict[str, Any]) -> list[Path]:
    module_root = _module_root(module)
    install_dir = _module_install_dir(module)
    candidates = [
        install_dir / "pyproject.toml",
        module_root / "pyproject.toml",
        install_dir / "poetry.lock",
        module_root / "poetry.lock",
        install_dir / "requirements.txt",
        module_root / "requirements.txt",
        module_root / "backend" / "requirements.txt",
        install_dir / "requirements-dev.txt",
        module_root / "requirements-dev.txt",
    ]
    seen: set[Path] = set()
    existing: list[Path] = []
    for candidate in candidates:
        if candidate.exists() and candidate not in seen:
            seen.add(candidate)
            existing.append(candidate)
    return existing


def _hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def _status_for_health_response(
    status_code: int,
    preflight_status: str,
) -> int:
    if status_code == HTTPStatus.SERVICE_UNAVAILABLE or preflight_status == PREFLIGHT_DEGRADED:
        return STATUS_INDEX["degraded"]
    return STATUS_INDEX["running"]


def _message_from_probe_outcome(
    outcome: dict[str, Any],
    *,
    optional: bool,
) -> str:
    import_name = str(outcome.get("import", "unknown"))
    missing_name = str(outcome.get("missing") or import_name)
    if outcome.get("kind") == "missing":
        if optional:
            return (
                f"Optional capability unavailable: {missing_name} "
                f"(needed by {import_name})"
            )
        if missing_name == import_name:
            return f"Missing required import: {missing_name}"
        return f"Missing required dependency: {missing_name} (needed by {import_name})"

    error = str(outcome.get("error") or "Unknown import failure")
    if optional:
        return f"Optional capability check failed for {import_name}: {error}"
    return f"Required import check failed for {import_name}: {error}"


def _doctor_prefix(status: str) -> str:
    return (
        "preflight failed"
        if status == PREFLIGHT_FAILED
        else "degraded optional capability"
        if status == PREFLIGHT_DEGRADED
        else "OK"
    )


def _flutter_sdk_check() -> dict[str, Any]:
    flutter = shutil.which("flutter")
    if flutter is None:
        return {
            "id": "flutter-sdk",
            "name": "Flutter SDK",
            "preflightStatus": PREFLIGHT_FAILED,
            "preflightMessage": "Flutter executable not found on PATH",
            "capabilityWarnings": [],
        }

    flutter_path = Path(flutter).resolve()
    cache_dir = flutter_path.parent / "cache"
    engine_stamp = cache_dir / "engine.stamp"

    if not cache_dir.exists():
        return {
            "id": "flutter-sdk",
            "name": "Flutter SDK",
            "preflightStatus": PREFLIGHT_FAILED,
            "preflightMessage": f"Flutter SDK cache directory missing: {cache_dir}",
            "capabilityWarnings": [],
        }

    if not os.access(cache_dir, os.W_OK):
        return {
            "id": "flutter-sdk",
            "name": "Flutter SDK",
            "preflightStatus": PREFLIGHT_FAILED,
            "preflightMessage": f"Flutter SDK cache is not writable: {cache_dir}",
            "capabilityWarnings": [],
        }

    if engine_stamp.exists() and not os.access(engine_stamp, os.W_OK):
        return {
            "id": "flutter-sdk",
            "name": "Flutter SDK",
            "preflightStatus": PREFLIGHT_FAILED,
            "preflightMessage": f"Flutter SDK cache stamp is not writable: {engine_stamp}",
            "capabilityWarnings": [],
        }

    return {
        "id": "flutter-sdk",
        "name": "Flutter SDK",
        "preflightStatus": PREFLIGHT_OK,
        "preflightMessage": f"Flutter SDK cache ready: {cache_dir}",
        "capabilityWarnings": [],
    }


def _global_preflight_checks() -> list[dict[str, Any]]:
    return [_flutter_sdk_check()]


def _render_doctor_report(report: dict[str, Any]) -> str:
    summary = (
        "preflight failed"
        if report["fatalCount"] > 0
        else "degraded optional capability"
        if report["degradedCount"] > 0
        else "ok"
    )
    lines = [
        "NMTK launcher doctor",
        f"status={summary}",
        f"fatal={report['fatalCount']} degraded={report['degradedCount']} ok={report['okCount']}",
    ]
    for check in report.get("globalChecks", []):
        lines.append(
            f"{_doctor_prefix(str(check['preflightStatus']))} {check['id']}: "
            f"{check['preflightMessage'] or 'ready'}"
        )
        for warning in check.get("capabilityWarnings", []):
            lines.append(f"  - {warning}")
    for module in report["modules"]:
        lines.append(
            f"{_doctor_prefix(str(module['preflightStatus']))} {module['id']}: "
            f"{module['preflightMessage'] or 'ready'}"
        )
        for warning in module.get("capabilityWarnings", []):
            lines.append(f"  - {warning}")
    return "\n".join(lines)


def _dedupe_messages(messages: list[str]) -> list[str]:
    seen: set[str] = set()
    deduped: list[str] = []
    for message in messages:
        if message not in seen:
            seen.add(message)
            deduped.append(message)
    return deduped


@dataclass
class ManagedProcess:
    """Represents a launched module process and its recent logs."""

    process: subprocess.Popen[str]
    logs: collections.deque[str] = field(
        default_factory=lambda: collections.deque(maxlen=LOG_LINE_LIMIT)
    )


@dataclass
class PreflightResult:
    """Outcome of a non-network module readiness probe."""

    status: str
    message: str | None = None
    capability_warnings: list[str] = field(default_factory=list)
    environment_fingerprint: str | None = None

    def state_fields(self) -> dict[str, Any]:
        return {
            "preflightStatus": self.status,
            "preflightMessage": self.message,
            "capabilityWarnings": list(self.capability_warnings),
            "environmentFingerprint": self.environment_fingerprint,
        }


class LauncherControlState:
    """In-memory state and lifecycle orchestration for module control."""

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._terminal_lock = threading.Lock()
        self._modules = self._load_modules()
        self._processes: dict[str, ManagedProcess] = {}
        self._logs: dict[str, collections.deque[str]] = collections.defaultdict(
            lambda: collections.deque(maxlen=LOG_LINE_LIMIT)
        )
        self._tasks: dict[str, threading.Thread] = {}
        self._settings = self._load_settings()
        self._shutdown = threading.Event()
        self._health_thread = threading.Thread(
            target=self._health_poll_loop,
            name="launcher-control-health",
            daemon=True,
        )
        self._health_thread.start()

    def shutdown(self) -> None:
        self._shutdown.set()
        with self._lock:
            module_ids = list(self._processes.keys())
        for module_id in module_ids:
            self.stop_module(module_id)

    def _load_modules(self) -> dict[str, dict[str, Any]]:
        manifest = _read_json_file(MODULES_MANIFEST, [])
        remote_versions = {
            item["id"]: item["version"]
            for item in _read_json_file(REMOTE_MANIFEST, [])
            if isinstance(item, dict) and "id" in item and "version" in item
        }
        saved_states = _read_json_file(STATE_FILE, {})
        module_map: dict[str, dict[str, Any]] = {}
        for raw in manifest:
            if not isinstance(raw, dict) or "id" not in raw:
                continue
            module_id = str(raw["id"])
            saved = saved_states.get(module_id, {})
            module = dict(raw)
            module["directory"] = str(_module_root(module))
            module["remoteVersion"] = remote_versions.get(module_id, "0.0.0")
            module["versionPinned"] = bool(saved.get("versionPinned", False))
            module["version"] = str(saved.get("version", module.get("version", "0.0.0")))
            module["isEnabled"] = bool(saved.get("isEnabled", True))
            module["customPort"] = saved.get("customPort")
            status_index = saved.get("status", STATUS_INDEX["notInstalled"])
            if status_index in (
                STATUS_INDEX["running"],
                STATUS_INDEX["starting"],
                STATUS_INDEX["stopping"],
                STATUS_INDEX["degraded"],
                STATUS_INDEX["error"],
                STATUS_INDEX["updating"],
            ):
                status_index = STATUS_INDEX["installed"]
            module["status"] = status_index
            module["installProgress"] = float(saved.get("installProgress", 0.0))
            module["healthStatus"] = saved.get("healthStatus")
            module["requiredImports"] = _module_required_imports(module)
            module["optionalImports"] = _module_optional_imports(module)
            module["installStrategy"] = _module_install_strategy(module)
            module["startStrategy"] = _module_start_strategy(module)
            module["preflightStatus"] = str(saved.get("preflightStatus", PREFLIGHT_OK))
            module["preflightMessage"] = saved.get("preflightMessage")
            module["capabilityWarnings"] = _normalized_import_list(
                saved.get("capabilityWarnings", module.get("capabilityWarnings", []))
            )
            module["environmentFingerprint"] = saved.get("environmentFingerprint")
            module_map[module_id] = module
        return module_map

    def _load_settings(self) -> dict[str, Any]:
        defaults = {
            "logLevel": DEFAULT_CONTROL_LOG_LEVEL,
            "mujocoAvailable": _mujoco_available(),
            "pythonAvailable": True,
        }
        stored = _read_json_file(SETTINGS_FILE, {})
        if not isinstance(stored, dict):
            return defaults
        defaults.update(
            {
                "logLevel": stored.get("logLevel", DEFAULT_CONTROL_LOG_LEVEL),
                "mujocoAvailable": _mujoco_available(),
                "pythonAvailable": True,
            }
        )
        return defaults

    def serialize_modules(self) -> list[dict[str, Any]]:
        with self._lock:
            return [self._serialize_module(module) for module in self._modules.values()]

    def serialize_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            return self._serialize_module(module)

    def _serialize_module(self, module: dict[str, Any]) -> dict[str, Any]:
        payload = dict(module)
        payload["directory"] = module["directory"]
        payload["effectivePort"] = _effective_port(module)
        return payload

    def get_settings(self) -> dict[str, Any]:
        with self._lock:
            return {
                "logLevel": self._settings["logLevel"],
                "mujocoAvailable": self._settings["mujocoAvailable"],
                "pythonAvailable": self._settings["pythonAvailable"],
            }

    def update_settings(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            log_level = payload.get("logLevel")
            if isinstance(log_level, str) and log_level:
                self._settings["logLevel"] = log_level.lower()
            _write_json_file(SETTINGS_FILE, self._settings)
            return self.get_settings()

    def update_module_settings(self, module_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            if "isEnabled" in payload:
                module["isEnabled"] = bool(payload["isEnabled"])
            if "customPort" in payload:
                custom_port = payload["customPort"]
                module["customPort"] = custom_port if isinstance(custom_port, int) else None
            if "versionPinned" in payload:
                module["versionPinned"] = bool(payload["versionPinned"])
            self._persist_states()
            return self._serialize_module(module)

    def install_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            if self._task_running(module_id):
                return self._serialize_module(module)
            module["status"] = STATUS_INDEX["installing"]
            module["installProgress"] = 0.0
            module["healthStatus"] = None
            module["preflightStatus"] = PREFLIGHT_OK
            module["preflightMessage"] = None
            module["capabilityWarnings"] = []
            self._persist_states()
            self._spawn_task(module_id, lambda: self._install_sync(module_id))
            return self._serialize_module(module)

    def update_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            if self._task_running(module_id):
                return self._serialize_module(module)
            module["status"] = STATUS_INDEX["updating"]
            module["installProgress"] = 0.0
            module["healthStatus"] = None
            module["preflightStatus"] = PREFLIGHT_OK
            module["preflightMessage"] = None
            module["capabilityWarnings"] = []
            self._persist_states()
            self._spawn_task(module_id, lambda: self._update_sync(module_id))
            return self._serialize_module(module)

    def start_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            if self._task_running(module_id):
                return self._serialize_module(module)
            module["status"] = STATUS_INDEX["starting"]
            module["healthStatus"] = None
            module["preflightStatus"] = PREFLIGHT_OK
            module["preflightMessage"] = None
            module["capabilityWarnings"] = []
            self._persist_states()
            self._spawn_task(module_id, lambda: self._start_sync(module_id))
            return self._serialize_module(module)

    def stop_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            module["status"] = STATUS_INDEX["stopping"]
            self._persist_states()
        try:
            self._stop_process(module_id)
            self._update_module_fields(
                module_id,
                status=STATUS_INDEX["installed"],
                healthStatus=None,
                installProgress=1.0,
            )
        except Exception as exc:  # noqa: BLE001
            self._set_error(module_id, f"Stop failed: {exc}")
        return self.serialize_module(module_id)

    def uninstall_module(self, module_id: str) -> dict[str, Any]:
        self.stop_module(module_id)
        self._cleanup_module_environment(module_id)
        self._update_module_fields(
            module_id,
            status=STATUS_INDEX["notInstalled"],
            installProgress=0.0,
            healthStatus=None,
            preflightStatus=PREFLIGHT_OK,
            preflightMessage=None,
            capabilityWarnings=[],
            environmentFingerprint=None,
        )
        return self.serialize_module(module_id)

    def get_logs(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            managed = self._processes.get(module_id)
            lines = managed.logs if managed is not None else self._logs[module_id]
            return {"moduleId": module_id, "lines": list(lines)}

    def _task_running(self, module_id: str) -> bool:
        task = self._tasks.get(module_id)
        return task is not None and task.is_alive()

    def _spawn_task(self, module_id: str, target: Callable[[], None]) -> None:
        thread = threading.Thread(target=self._run_task, args=(module_id, target), daemon=True)
        self._tasks[module_id] = thread
        thread.start()

    def _run_task(self, module_id: str, target: Callable[[], None]) -> None:
        try:
            target()
        except Exception as exc:  # noqa: BLE001
            self._set_error(module_id, str(exc))
        finally:
            with self._lock:
                self._tasks.pop(module_id, None)

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
                result.stderr.strip() or f"Failed to inspect Python version at {python_path}"
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
        except Exception:
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
            self._append_log(module["id"], result.stderr, stderr=True, emit_terminal=True)
        if result.stdout:
            for line in result.stdout.splitlines():
                if not line.startswith(PREFLIGHT_SENTINEL):
                    self._append_log(module["id"], line, emit_terminal=True)

        sentinel_line = next(
            (line for line in result.stdout.splitlines() if line.startswith(PREFLIGHT_SENTINEL)),
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
        capability_warnings = _dedupe_messages([
            _message_from_probe_outcome(outcome, optional=True)
            for outcome in payload.get("optional", [])
            if not outcome.get("ok")
        ])

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

    def _preflight_module(self, module: dict[str, Any], *, allow_repair: bool) -> PreflightResult:
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
        repaired_result.environment_fingerprint = self._compute_environment_fingerprint(module)
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
        venv_pip = _module_venv_pip(module)
        poetry = _poetry_command()
        use_poetry = _module_uses_poetry(module) and poetry is not None

        self._update_module_fields(module_id, status=STATUS_INDEX["installing"], installProgress=0.1)
        if use_poetry:
            # Configure Poetry before any `poetry run ...` command so repairs
            # consistently recreate an in-project `.venv`.
            self._run_command(
                [poetry, "config", "virtualenvs.in-project", "true", "--local"],
                cwd=install_dir,
                module_id=module_id,
            )
        if not use_poetry and not venv_python.exists():
            self._run_command(
                [sys.executable, "-m", "venv", "venv"],
                cwd=install_dir,
                module_id=module_id,
            )

        self._update_module_fields(module_id, installProgress=0.3)
        for dependency in module.get("localDeps", []):
            dep_path = (REPO_ROOT / dependency).resolve()
            if dep_path.exists():
                if use_poetry:
                    self._run_command(
                        [poetry, "run", "python", "-m", "pip", "install", str(dep_path)],
                        cwd=install_dir,
                        module_id=module_id,
                    )
                else:
                    self._run_command(
                        [str(venv_pip), "install", str(dep_path)],
                        cwd=install_dir,
                        module_id=module_id,
                    )

        self._update_module_fields(module_id, installProgress=0.6)
        if use_poetry:
            self._run_command(
                [poetry, "lock"],
                cwd=install_dir,
                module_id=module_id,
            )
            self._run_command(
                [poetry, "install", "--no-interaction", "--no-root"],
                cwd=install_dir,
                module_id=module_id,
            )
        else:
            self._run_command(
                [str(venv_pip), "install", "."],
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
                self._persist_states()

    def _start_sync(self, module_id: str) -> None:
        module = self._get_module(module_id)
        if not module.get("isEnabled", True):
            raise RuntimeError("Module is disabled")

        preflight = self._preflight_module(module, allow_repair=True)
        self._update_module_fields(module_id, **preflight.state_fields())
        if preflight.status == PREFLIGHT_FAILED:
            self._update_module_fields(
                module_id,
                status=STATUS_INDEX["error"],
                healthStatus=preflight.message,
            )
            raise RuntimeError(preflight.message or "Module preflight failed")

        module = self._get_module(module_id)
        start_strategy = _module_start_strategy(module)
        if start_strategy == "none":
            raise RuntimeError(f"Module '{module_id}' does not define a runnable backend")
        if start_strategy not in SUPPORTED_START_STRATEGIES:
            raise RuntimeError(
                f"Unsupported start strategy '{start_strategy}' for {module_id}"
            )

        port = _effective_port(module)
        if port is None:
            raise RuntimeError("Module has no configured port")

        self._kill_process_on_port(port, module_id=module_id)
        run_dir = _module_run_dir(module)
        python_path = _module_python_path(module)
        if not python_path.exists():
            raise RuntimeError(_missing_python_message(module, python_path))

        command = [
            str(python_path),
            "-m",
            "uvicorn",
            str(module.get("uvicornTarget", "app.main:app")),
            "--host",
            _uvicorn_host(),
            "--port",
            str(port),
            "--log-level",
            str(self._settings["logLevel"]),
        ]
        process = subprocess.Popen(
            command,
            cwd=run_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            stdin=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
        managed = ManagedProcess(process=process, logs=self._logs[module_id])
        with self._lock:
            self._processes[module_id] = managed
            self._persist_states()
        self._stream_logs(module_id, managed)
        self._watch_process_exit(module_id, managed)

        deadline = time.monotonic() + STARTUP_GRACE_SECONDS
        while time.monotonic() < deadline:
            ok, status_code, health_text = self._probe_health(module)
            if ok:
                next_status = _status_for_health_response(status_code, preflight.status)
                self._update_module_fields(
                    module_id,
                    status=next_status,
                    installProgress=1.0,
                    healthStatus=health_text,
                )
                return
            if process.poll() is not None:
                raise RuntimeError(f"Process exited with code {process.returncode}")
            time.sleep(0.5)

        self._update_module_fields(
            module_id,
            status=STATUS_INDEX["error"],
            healthStatus="Timed out waiting for /health",
        )

    def _stream_logs(self, module_id: str, managed: ManagedProcess) -> None:
        def _pump(stream: Any, *, stderr: bool = False) -> None:
            if stream is None:
                return
            for line in stream:
                self._append_log(module_id, line, stderr=stderr, emit_terminal=True)

        if managed.process.stdout is not None:
            threading.Thread(
                target=_pump,
                args=(managed.process.stdout,),
                daemon=True,
                name=f"{module_id}-stdout",
            ).start()
        if managed.process.stderr is not None:
            threading.Thread(
                target=_pump,
                args=(managed.process.stderr,),
                kwargs={"stderr": True},
                daemon=True,
                name=f"{module_id}-stderr",
            ).start()

    def _watch_process_exit(self, module_id: str, managed: ManagedProcess) -> None:
        def _watch() -> None:
            return_code = managed.process.wait()
            with self._lock:
                current = self._processes.get(module_id)
                if current is managed:
                    self._processes.pop(module_id, None)
            if self._shutdown.is_set():
                return
            if self.serialize_module(module_id)["status"] == STATUS_INDEX["stopping"]:
                return
            self._set_error(module_id, f"Process exited with code {return_code}")

        threading.Thread(
            target=_watch,
            daemon=True,
            name=f"{module_id}-exit-watch",
        ).start()

    def _stop_process(self, module_id: str) -> None:
        with self._lock:
            managed = self._processes.pop(module_id, None)
        if managed is None:
            return
        managed.process.terminate()
        try:
            managed.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            managed.process.kill()
            managed.process.wait(timeout=5)

    def _probe_health(self, module: dict[str, Any]) -> tuple[bool, int, str | None]:
        port = _effective_port(module)
        if port is None:
            return False, 0, None
        url = f"http://127.0.0.1:{port}/health"
        try:
            with urllib.request.urlopen(url, timeout=2.0) as response:
                body = response.read().decode("utf-8", errors="replace")
                return True, int(response.status), body
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            if exc.code in (HTTPStatus.NOT_FOUND, HTTPStatus.SERVICE_UNAVAILABLE):
                return True, int(exc.code), body
            return False, int(exc.code), body
        except (urllib.error.URLError, TimeoutError, socket.timeout):
            return False, 0, None

    def _health_poll_loop(self) -> None:
        while not self._shutdown.wait(HEALTH_POLL_SECONDS):
            with self._lock:
                module_ids = list(self._processes.keys())
            for module_id in module_ids:
                with self._lock:
                    module = dict(self._get_module(module_id))
                ok, status_code, health_text = self._probe_health(module)
                if ok:
                    next_status = _status_for_health_response(
                        status_code,
                        str(module.get("preflightStatus", PREFLIGHT_OK)),
                    )
                    self._update_module_fields(
                        module_id,
                        status=next_status,
                        healthStatus=health_text
                        if health_text
                        else ("No /health endpoint (server is up)" if status_code == 404 else None),
                    )
                elif module_id in self._processes:
                    self._update_module_fields(
                        module_id,
                        status=STATUS_INDEX["error"],
                        healthStatus="Health probe failed",
                    )

    def _run_command(self, command: list[str], cwd: Path, module_id: str) -> None:
        result = subprocess.run(
            command,
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.stdout:
            self._append_log(module_id, result.stdout, emit_terminal=True)
        if result.stderr:
            self._append_log(module_id, result.stderr, stderr=True, emit_terminal=True)
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or f"Command failed: {' '.join(command)}")

    def _append_log(
        self,
        module_id: str,
        text: str,
        *,
        stderr: bool = False,
        emit_terminal: bool = False,
    ) -> None:
        terminal_lines: list[str] = []
        with self._lock:
            lines = self._logs[module_id]
            managed = self._processes.get(module_id)
            for line in text.splitlines():
                if line.strip():
                    clean_line = line.rstrip()
                    stored_line = f"[stderr] {clean_line}" if stderr else clean_line
                    lines.append(stored_line)
                    if managed is not None and managed.logs is not lines:
                        managed.logs.append(stored_line)
                    if emit_terminal:
                        terminal_lines.append(clean_line)

        if emit_terminal:
            for line in terminal_lines:
                self._emit_terminal_log(module_id, line, stderr=stderr)

    def _emit_terminal_log(self, module_id: str, line: str, *, stderr: bool = False) -> None:
        stream = sys.stderr if stderr else sys.stdout
        with self._terminal_lock:
            print(f"[{module_id}] {line}", file=stream, flush=True)

    def _kill_process_on_port(self, port: int, module_id: str) -> None:
        if os.name == "nt":
            return
        result = subprocess.run(
            ["lsof", "-ti", f":{port}"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            return
        for pid_text in result.stdout.splitlines():
            pid_text = pid_text.strip()
            if not pid_text:
                continue
            try:
                os.kill(int(pid_text), 9)
                self._append_log(module_id, f"Killed stale process {pid_text} on port {port}")
            except OSError:
                continue

    def doctor_report(self) -> dict[str, Any]:
        modules: list[dict[str, Any]] = []
        global_checks = _global_preflight_checks()
        fatal_count = 0
        degraded_count = 0
        ok_count = 0

        for check in global_checks:
            status = str(check.get("preflightStatus", PREFLIGHT_OK))
            if status == PREFLIGHT_FAILED:
                fatal_count += 1
            elif status == PREFLIGHT_DEGRADED:
                degraded_count += 1
            else:
                ok_count += 1

        with self._lock:
            snapshot = [dict(module) for module in self._modules.values()]

        for module in snapshot:
            if not module.get("isEnabled", True):
                result = PreflightResult(
                    status=PREFLIGHT_OK,
                    message="Module disabled",
                )
            elif _module_start_strategy(module) == "none":
                result = PreflightResult(
                    status=PREFLIGHT_OK,
                    message="No runnable backend configured",
                )
            else:
                result = self._preflight_module(module, allow_repair=False)

            if result.status == PREFLIGHT_FAILED:
                fatal_count += 1
            elif result.status == PREFLIGHT_DEGRADED:
                degraded_count += 1
            else:
                ok_count += 1

            modules.append(
                {
                    "id": module["id"],
                    "name": module["name"],
                    "status": _status_name(int(module.get("status", 0))),
                    "preflightStatus": result.status,
                    "preflightMessage": result.message,
                    "capabilityWarnings": list(result.capability_warnings),
                    "environmentFingerprint": result.environment_fingerprint,
                    "effectivePort": _effective_port(module),
                }
            )

        return {
            "status": "ok" if fatal_count == 0 else "error",
            "fatalCount": fatal_count,
            "degradedCount": degraded_count,
            "okCount": ok_count,
            "globalChecks": global_checks,
            "modules": modules,
        }

    def _set_error(self, module_id: str, message: str) -> None:
        self._update_module_fields(
            module_id,
            status=STATUS_INDEX["error"],
            healthStatus=message,
        )

    def _get_module(self, module_id: str) -> dict[str, Any]:
        try:
            return self._modules[module_id]
        except KeyError as exc:
            raise KeyError(f"Unknown module '{module_id}'") from exc

    def _update_module_fields(self, module_id: str, **fields: Any) -> None:
        with self._lock:
            module = self._get_module(module_id)
            for key, value in fields.items():
                module[key] = value
            self._persist_states()

    def _persist_states(self) -> None:
        payload = {
            module_id: {
                "id": module["id"],
                "version": module.get("version", "0.0.0"),
                "remoteVersion": module.get("remoteVersion", "0.0.0"),
                "versionPinned": bool(module.get("versionPinned", False)),
                "isEnabled": bool(module.get("isEnabled", True)),
                "customPort": module.get("customPort"),
                "status": module.get("status", STATUS_INDEX["notInstalled"]),
                "installProgress": float(module.get("installProgress", 0.0)),
                "healthStatus": module.get("healthStatus"),
                "preflightStatus": module.get("preflightStatus", PREFLIGHT_OK),
                "preflightMessage": module.get("preflightMessage"),
                "capabilityWarnings": list(module.get("capabilityWarnings", [])),
                "environmentFingerprint": module.get("environmentFingerprint"),
                "directory": module["directory"],
                "port": module.get("port"),
                "hasFrontend": bool(module.get("hasFrontend", False)),
                "frontendStatus": module.get("frontendStatus", "No"),
                "requiresMuJoCo": bool(module.get("requiresMuJoCo", False)),
                "sourcePath": module.get("sourcePath", "."),
                "runPath": module.get("runPath", "."),
                "uvicornTarget": module.get("uvicornTarget", "app.main:app"),
                "requiredImports": list(module.get("requiredImports", [])),
                "optionalImports": list(module.get("optionalImports", [])),
                "installStrategy": module.get("installStrategy", "pip"),
                "startStrategy": module.get("startStrategy", "uvicorn"),
            }
            for module_id, module in self._modules.items()
        }
        _write_json_file(STATE_FILE, payload)


class LauncherControlHandler(BaseHTTPRequestHandler):
    """HTTP adapter exposing launcher control state over a JSON API."""

    server: "LauncherControlServer"

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._send_json(HTTPStatus.NO_CONTENT, {})

    def do_GET(self) -> None:  # noqa: N802
        self._dispatch("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._dispatch("POST")

    def do_PUT(self) -> None:  # noqa: N802
        self._dispatch("PUT")

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _dispatch(self, method: str) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        body = self._read_body()
        try:
            if method == "GET" and path == "/health":
                self._send_json(
                    HTTPStatus.OK,
                    {
                        "status": "ok",
                        **self.server.state.get_settings(),
                    },
                )
                return

            if method == "GET" and path == "/api/launcher/modules":
                self._send_json(HTTPStatus.OK, self.server.state.serialize_modules())
                return

            if method == "GET" and path == "/api/launcher/doctor":
                self._send_json(HTTPStatus.OK, self.server.state.doctor_report())
                return

            if method == "GET" and path == "/api/launcher/settings":
                self._send_json(HTTPStatus.OK, self.server.state.get_settings())
                return

            if method == "PUT" and path == "/api/launcher/settings":
                self._send_json(
                    HTTPStatus.OK,
                    self.server.state.update_settings(body or {}),
                )
                return

            segments = [segment for segment in path.split("/") if segment]
            if len(segments) >= 4 and segments[:3] == ["api", "launcher", "modules"]:
                module_id = segments[3]
                if len(segments) == 4 and method == "GET":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.serialize_module(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "logs" and method == "GET":
                    self._send_json(HTTPStatus.OK, self.server.state.get_logs(module_id))
                    return
                if len(segments) == 5 and segments[4] == "install" and method == "POST":
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.install_module(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "start" and method == "POST":
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.start_module(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "stop" and method == "POST":
                    self._send_json(HTTPStatus.OK, self.server.state.stop_module(module_id))
                    return
                if len(segments) == 5 and segments[4] == "uninstall" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.uninstall_module(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "update" and method == "POST":
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.update_module(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "settings" and method == "PUT":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.update_module_settings(module_id, body or {}),
                    )
                    return

            self._send_json(HTTPStatus.NOT_FOUND, {"error": f"Unknown route: {path}"})
        except KeyError as exc:
            self._send_json(HTTPStatus.NOT_FOUND, {"error": str(exc)})
        except Exception as exc:  # noqa: BLE001
            self._send_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {"error": str(exc), "path": path, "method": method},
            )

    def _read_body(self) -> dict[str, Any] | None:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return None
        raw = self.rfile.read(length)
        if not raw:
            return None
        try:
            payload = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            return None
        return payload if isinstance(payload, dict) else None

    def _send_json(self, status: HTTPStatus, payload: Any) -> None:
        encoded = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
        self.end_headers()
        if status != HTTPStatus.NO_CONTENT:
            self.wfile.write(encoded)


class LauncherControlServer(ThreadingHTTPServer):
    """HTTP server bound to a shared launcher state."""

    daemon_threads = True

    def __init__(self, server_address: tuple[str, int]) -> None:
        self.state = LauncherControlState()
        super().__init__(server_address, LauncherControlHandler)

    def server_close(self) -> None:
        self.state.shutdown()
        super().server_close()


def create_server(host: str, port: int) -> LauncherControlServer:
    return LauncherControlServer((host, port))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Launcher control service")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8090)
    parser.add_argument(
        "--doctor",
        action="store_true",
        help="Run a non-mutating launcher environment diagnostic and exit",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="When used with --doctor, print the report as JSON",
    )
    args = parser.parse_args(argv)

    if args.doctor:
        state = LauncherControlState()
        try:
            report = state.doctor_report()
        finally:
            state.shutdown()
        if args.json:
            print(json.dumps(report, indent=2, sort_keys=True))
        else:
            print(_render_doctor_report(report))
        return 1 if report["fatalCount"] else 0

    server = create_server(args.host, args.port)
    print(f"Launcher control service listening on http://{args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
