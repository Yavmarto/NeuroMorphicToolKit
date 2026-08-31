"""Shared contracts and process execution for launcher deployments."""

from __future__ import annotations

import os
import queue
import shutil
import subprocess
import threading
import time
import urllib.request
from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from types import TracebackType
from typing import Literal, Protocol, cast

from .config import REPO_ROOT
from .deployment_contracts import DeploymentTarget, redact_text

ProgressCallback = Callable[[str, str, float], None]
LogCallback = Callable[[str], None]
SecretResolver = Callable[[str], str]


def _redact_value(value: str, sensitive_values: Iterable[str]) -> str:
    """Return launcher-safe command output without retained secrets."""
    redacted = redact_text(value)
    for secret in sensitive_values:
        if secret:
            redacted = redacted.replace(secret, "<redacted>")
    return redacted


@dataclass(frozen=True, slots=True)
class CommandResult:
    """Redacted, structured outcome from one child process."""

    returncode: int
    stdout: str
    stderr: str
    timed_out: bool = False


class CommandRunnerProtocol(Protocol):
    """Typed process boundary shared by deployment executors."""

    def run(
        self,
        argv: Sequence[str],
        *,
        cwd: str | None = None,
        env: Mapping[str, str] | None = None,
        timeout: float | None = None,
        capture_output: Literal[True] = True,
        text: Literal[True] = True,
        check: Literal[False] = False,
        sensitive_values: Iterable[str] = (),
    ) -> CommandResult: ...

    def stream(
        self,
        argv: Sequence[str],
        *,
        env: Mapping[str, str] | None = None,
        timeout: float,
        on_line: LogCallback,
        sensitive_values: Iterable[str] = (),
    ) -> CommandResult: ...


class HttpResponseProtocol(Protocol):
    """HTTP response surface used by deployment readiness probes."""

    status: int

    def read(self) -> bytes: ...

    def __enter__(self) -> HttpResponseProtocol: ...

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None: ...


class SubprocessCommandRunner:
    """Execute bounded child processes and return redacted results."""

    def run(
        self,
        argv: Sequence[str],
        *,
        cwd: str | None = None,
        env: Mapping[str, str] | None = None,
        timeout: float | None = None,
        capture_output: Literal[True] = True,
        text: Literal[True] = True,
        check: Literal[False] = False,
        sensitive_values: Iterable[str] = (),
    ) -> CommandResult:
        try:
            completed = subprocess.run(
                list(argv),
                cwd=cwd,
                capture_output=capture_output,
                text=text,
                check=check,
                timeout=timeout,
                env=dict(env) if env is not None else None,
            )
        except subprocess.TimeoutExpired as exc:
            return CommandResult(
                returncode=-1,
                stdout=_redact_value(str(exc.stdout or ""), sensitive_values),
                stderr=_redact_value(str(exc.stderr or ""), sensitive_values),
                timed_out=True,
            )
        return CommandResult(
            returncode=completed.returncode,
            stdout=_redact_value(completed.stdout or "", sensitive_values),
            stderr=_redact_value(completed.stderr or "", sensitive_values),
        )

    def stream(
        self,
        argv: Sequence[str],
        *,
        env: Mapping[str, str] | None = None,
        timeout: float,
        on_line: LogCallback,
        sensitive_values: Iterable[str] = (),
    ) -> CommandResult:
        process = subprocess.Popen(
            list(argv),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=dict(env) if env is not None else None,
        )
        line_queue: queue.Queue[str | None] = queue.Queue()

        def _drain_stdout() -> None:
            assert process.stdout is not None
            for line in iter(process.stdout.readline, ""):
                line_queue.put(line)
            line_queue.put(None)

        reader = threading.Thread(target=_drain_stdout, daemon=True)
        reader.start()
        output_lines: list[str] = []
        started_at = time.monotonic()
        stream_closed = False
        while True:
            if time.monotonic() - started_at > timeout:
                process.kill()
                process.wait()
                return CommandResult(
                    returncode=-1,
                    stdout="\n".join(output_lines),
                    stderr="",
                    timed_out=True,
                )
            try:
                item = line_queue.get(timeout=0.25)
            except queue.Empty:
                pass
            else:
                if item is None:
                    stream_closed = True
                else:
                    line = _redact_value(item.rstrip("\r\n"), sensitive_values)
                    if line:
                        output_lines.append(line)
                        if len(output_lines) > 40:
                            del output_lines[0]
                        on_line(line)
            if stream_closed and process.poll() is not None:
                break
        return CommandResult(
            returncode=process.wait(),
            stdout="\n".join(output_lines),
            stderr="",
        )


def _bundled_or_path(name: str) -> str | None:
    """Resolve a bundled external CLI before falling back to ``PATH``."""
    bundled = REPO_ROOT / "bin" / name
    if bundled.is_file() and os.access(bundled, os.X_OK):
        return str(bundled)
    return shutil.which(name)


def build_ssh_argv(
    port: int, *, key_path: str | None, password: str | None
) -> tuple[list[str], dict[str, str]]:
    """Build a secret-safe SSH argv prefix and its extra environment."""
    ssh_cmd = [
        "ssh",
        "-p",
        str(port or 22),
        "-o",
        "StrictHostKeyChecking=no",
    ]
    if key_path:
        ssh_cmd.extend(["-o", "BatchMode=yes", "-i", key_path])
        return ssh_cmd, {}
    if password:
        sshpass = _bundled_or_path("sshpass")
        if sshpass is None:
            raise RuntimeError(
                "sshpass is required for SSH password authentication but was not found"
            )
        return [sshpass, "-e"] + ssh_cmd, {"SSHPASS": password}
    ssh_cmd.extend(["-o", "BatchMode=yes"])
    return ssh_cmd, {}


class DeploymentExecutor:
    """Base class for one deployment mode."""

    def __init__(
        self,
        *,
        repo_root: Path,
        secret_resolver: SecretResolver | None = None,
        command_runner: CommandRunnerProtocol | None = None,
    ) -> None:
        self._repo_root = repo_root
        self._secret_resolver = secret_resolver
        self._commands = command_runner or SubprocessCommandRunner()
        self._log: LogCallback = lambda _line: None

    def run(
        self,
        target: DeploymentTarget,
        emit: ProgressCallback,
        log: LogCallback | None = None,
        clean_install: bool = False,
    ) -> None:
        raise NotImplementedError

    def _resolve_secret(self, ref: str) -> str:
        if self._secret_resolver is None:
            return ""
        return self._secret_resolver(ref)

    @staticmethod
    def _require_not_timed_out(
        result: CommandResult, *, operation: str, timeout: float
    ) -> None:
        """Map a structured timeout to a safe, actionable executor failure."""
        if result.timed_out:
            raise RuntimeError(f"{operation} timed out after {timeout:g}s")

    @staticmethod
    def _resolve_tool(name: str) -> str:
        return _bundled_or_path(name) or name

    @staticmethod
    def _open_url(url: str, *, timeout: float) -> HttpResponseProtocol:
        # typeshed leaves urlopen's concrete response as Any across Python
        # versions; the executors deliberately consume only this tiny protocol.
        return cast(HttpResponseProtocol, urllib.request.urlopen(url, timeout=timeout))


__all__ = [
    "CommandResult",
    "CommandRunnerProtocol",
    "DeploymentExecutor",
    "LogCallback",
    "ProgressCallback",
    "SecretResolver",
    "SubprocessCommandRunner",
    "build_ssh_argv",
]
