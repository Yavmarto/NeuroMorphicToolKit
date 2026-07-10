"""Generic process/log/health-probe mechanics — no install/update semantics.

Imported by ``server.py`` right before ``LauncherControlState`` is defined, so
the ``from .server import ...`` below resolves against the partially
initialized module rather than re-entering it — the names it pulls in must
already be bound in ``server.py`` above that import line.
"""

from __future__ import annotations

import collections
import os
import socket
import subprocess
import sys
import threading
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from http import HTTPStatus
from pathlib import Path
from typing import Any, Callable

from .module_environment import (
    _effective_port,
    _external_service_health_url,
    _is_externally_managed_service,
    _module_start_strategy,
)
from .server import LOG_LINE_LIMIT, PREFLIGHT_DEGRADED, STATUS_INDEX


@dataclass
class ManagedProcess:
    """Represents a launched module process and its recent logs."""

    process: subprocess.Popen[str]
    logs: collections.deque[str] = field(
        default_factory=lambda: collections.deque(maxlen=LOG_LINE_LIMIT)
    )


def _status_for_health_response(
    status_code: int,
    preflight_status: str,
) -> int:
    if (
        status_code == HTTPStatus.SERVICE_UNAVAILABLE
        or preflight_status == PREFLIGHT_DEGRADED
    ):
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


def _dedupe_messages(messages: list[str]) -> list[str]:
    seen: set[str] = set()
    deduped: list[str] = []
    for message in messages:
        if message not in seen:
            seen.add(message)
            deduped.append(message)
    return deduped


class ProcessSupervisionMixin:
    # ------------------------------------------------------------------
    # File-backed log endpoints
    # These serve the logs that the Flutter AnalyticsService writes to
    # ~/Documents/ — a path the sandboxed macOS app cannot read back
    # from itself, but the launcher control service (unsandboxed) can.
    # ------------------------------------------------------------------

    _LOG_FILE_MAX_BYTES: int = 262144  # 256 KiB tail
    _LOG_FILE_MAX_LINES: int = 2000

    @staticmethod
    def _read_log_file_tail(path: Path) -> list[str]:
        """Return up to _LOG_FILE_MAX_LINES lines from the tail of *path*.

        Returns a single-element list with an explanatory message when the
        file does not exist or cannot be read — identical sentinel behaviour to
        the Dart counterpart so the Flutter UI can handle both code paths
        identically.
        """
        if not path.exists():
            return ["No logs found."]
        try:
            size = path.stat().st_size
            max_bytes = ProcessSupervisionMixin._LOG_FILE_MAX_BYTES
            max_lines = ProcessSupervisionMixin._LOG_FILE_MAX_LINES
            start = max(0, size - max_bytes)
            with path.open("rb") as fh:
                fh.seek(start)
                raw = fh.read(size - start)
            text = raw.decode("utf-8", errors="replace")
            if start > 0:
                first_newline = text.find("\n")
                if 0 <= first_newline < len(text) - 1:
                    text = text[first_newline + 1:]
            lines = text.splitlines()
            if not lines:
                return ["No logs found."]
            return lines[-max_lines:] if len(lines) > max_lines else lines
        except OSError as exc:
            return [f"Failed to read logs: {exc}"]

    def _get_dart_analytics_dir(self) -> Path:
        if sys.platform == "darwin":
            return Path.home() / "Library" / "Application Support" / "com.example.neuroToolkit"
        elif sys.platform == "win32":
            return Path(os.environ.get("APPDATA", "")) / "com.example" / "neuroToolkit"
        else:
            return Path.home() / ".local" / "share" / "neuro_toolkit"

    def get_crash_log_lines(self) -> dict[str, Any]:
        """Serve the Dart AnalyticsService crash.log."""
        log_path = self._get_dart_analytics_dir() / "crash.log"
        return {"lines": self._read_log_file_tail(log_path)}

    def get_backend_activity_log_lines(self) -> dict[str, Any]:
        """Serve the Dart AnalyticsService launcher_backend_activity.log."""
        log_path = self._get_dart_analytics_dir() / "launcher_backend_activity.log"
        return {"lines": self._read_log_file_tail(log_path)}

    def _task_running(self, module_id: str) -> bool:
        task = self._tasks.get(module_id)
        return task is not None and task.is_alive()

    def _spawn_task(self, module_id: str, target: Callable[[], None]) -> None:
        thread = threading.Thread(
            target=self._run_task, args=(module_id, target), daemon=True
        )
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

        if _is_externally_managed_service(module):
            # Standalone service on its own port (e.g. Jupyter, lava_backend).
            # Use the health path from the deployment manifest and external probe host.
            url = _external_service_health_url(module, host=self._external_probe_host)
        elif _module_start_strategy(module) == "none":
            # Native feature module proxied through suite_api on the monolith port.
            # All mounted domain prefixes in suite_api are lowercase.
            url = f"http://127.0.0.1:{port}/api/{module['id'].lower()}/health"
        else:
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
            raise RuntimeError(
                result.stderr.strip() or f"Command failed: {' '.join(command)}"
            )

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

    def _emit_terminal_log(
        self, module_id: str, line: str, *, stderr: bool = False
    ) -> None:
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
                self._append_log(
                    module_id, f"Killed stale process {pid_text} on port {port}"
                )
            except OSError:
                continue
