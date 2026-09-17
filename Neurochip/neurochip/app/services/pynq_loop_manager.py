"""Manages the pynq_zmq_service control-loop process — local or via SSH."""

from __future__ import annotations

import logging
import os
import signal
import subprocess
import sys
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)

DEFAULT_ZMQ_PORT = 5555
DEFAULT_ZMQ_SERVICE_MODULE = "neurodreamhand.scripts.pynq_zmq_service"
DEFAULT_INSTALL_ROOT = "/opt/neurochip-pynq-agent"


class LoopProcessError(Exception):
    """Raised when the loop process cannot be started or stopped."""

    def __init__(self, message: str, *, error_code: str = "LOOP_ERROR") -> None:
        super().__init__(message)
        self.error_code = error_code


@dataclass
class LoopState:
    """Tracks the running control-loop process."""

    pid: int
    zmq_port: int
    ssh_host: str | None = None
    ssh_user: str = "xilinx"
    ssh_port: int = 22
    ssh_password: str | None = field(default=None, repr=False)
    ssh_key_path: str | None = None
    install_root: str = DEFAULT_INSTALL_ROOT

    @property
    def is_remote(self) -> bool:
        return self.ssh_host is not None


def _ssh_prefix(state: LoopState) -> list[str]:
    cmd: list[str] = []
    if state.ssh_password:
        cmd += ["sshpass", "-p", state.ssh_password]
    cmd += ["ssh", "-o", "StrictHostKeyChecking=no", "-p", str(state.ssh_port)]
    if state.ssh_key_path:
        cmd += ["-i", state.ssh_key_path]
    cmd.append(f"{state.ssh_user}@{state.ssh_host}")
    return cmd


# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------


def start_loop_local(
    *,
    zmq_port: int,
    bitstream_path: str,
    install_root: str = DEFAULT_INSTALL_ROOT,
) -> int:
    """Launch pynq_zmq_service as a background subprocess. Returns PID."""
    # Prefer the venv interpreter when the install root exists on-board.
    venv_python = os.path.join(install_root, "venv", "bin", "python")
    interpreter = venv_python if os.path.isfile(venv_python) else sys.executable

    cmd = [
        interpreter,
        "-m",
        DEFAULT_ZMQ_SERVICE_MODULE,
        "--port",
        str(zmq_port),
        "--bitstream",
        bitstream_path,
    ]
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except FileNotFoundError as exc:
        raise LoopProcessError(
            f"pynq_zmq_service module not found: {exc}",
            error_code="LOOP_MODULE_NOT_FOUND",
        ) from exc
    except OSError as exc:
        raise LoopProcessError(
            f"Failed to start loop process: {exc}",
            error_code="LOOP_START_FAILED",
        ) from exc

    logger.info("Started local loop process PID=%d zmq_port=%d", proc.pid, zmq_port)
    return proc.pid


def start_loop_ssh(
    *,
    ssh_host: str,
    ssh_user: str,
    zmq_port: int,
    bitstream_path: str,
    ssh_port: int = 22,
    ssh_password: str | None = None,
    ssh_key_path: str | None = None,
    install_root: str = DEFAULT_INSTALL_ROOT,
) -> int:
    """SSH into board, start pynq_zmq_service in background. Returns remote PID."""
    venv_python = f"{install_root}/venv/bin/python"
    # Background the service, redirect output, echo PID to stdout.
    remote_cmd = (
        f"cd {install_root} && "
        f"nohup {venv_python} -m {DEFAULT_ZMQ_SERVICE_MODULE} "
        f"--port {zmq_port} --bitstream {bitstream_path} "
        f"> /tmp/pynq_zmq_{zmq_port}.log 2>&1 & echo $!"
    )

    dummy = LoopState(
        pid=0,
        zmq_port=zmq_port,
        ssh_host=ssh_host,
        ssh_user=ssh_user,
        ssh_port=ssh_port,
        ssh_password=ssh_password,
        ssh_key_path=ssh_key_path,
        install_root=install_root,
    )
    ssh_cmd = _ssh_prefix(dummy) + [remote_cmd]

    try:
        result = subprocess.run(
            ssh_cmd,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise LoopProcessError(
            "SSH timed out while starting loop process",
            error_code="LOOP_SSH_TIMEOUT",
        ) from exc
    except FileNotFoundError as exc:
        raise LoopProcessError(
            f"SSH client not found: {exc}",
            error_code="LOOP_SSH_NOT_FOUND",
        ) from exc

    if result.returncode != 0:
        raise LoopProcessError(
            f"SSH exec failed (rc={result.returncode}): {result.stderr.strip()}",
            error_code="LOOP_SSH_FAILED",
        )

    pid_str = result.stdout.strip().splitlines()[-1] if result.stdout.strip() else ""
    try:
        pid = int(pid_str)
    except ValueError as exc:
        raise LoopProcessError(
            f"Could not parse remote PID from SSH output: {result.stdout!r}",
            error_code="LOOP_PID_PARSE_ERROR",
        ) from exc

    logger.info("Started remote loop PID=%d host=%s zmq_port=%d", pid, ssh_host, zmq_port)
    return pid


# ---------------------------------------------------------------------------
# Stop
# ---------------------------------------------------------------------------


def stop_loop_local(pid: int) -> None:
    """Send SIGTERM to the local loop process (idempotent if already gone)."""
    try:
        os.kill(pid, signal.SIGTERM)
        logger.info("Sent SIGTERM to local loop PID=%d", pid)
    except ProcessLookupError:
        logger.warning("Local loop PID=%d not found; already stopped", pid)


def stop_loop_ssh(state: LoopState) -> None:
    """SSH into board and kill the remote loop process (idempotent)."""
    kill_cmd = f"kill {state.pid} 2>/dev/null || true"
    ssh_cmd = _ssh_prefix(state) + [kill_cmd]

    try:
        result = subprocess.run(
            ssh_cmd,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise LoopProcessError(
            "SSH timed out while stopping loop process",
            error_code="LOOP_SSH_TIMEOUT",
        ) from exc
    except FileNotFoundError as exc:
        raise LoopProcessError(
            f"SSH client not found: {exc}",
            error_code="LOOP_SSH_NOT_FOUND",
        ) from exc

    if result.returncode != 0:
        raise LoopProcessError(
            f"SSH kill failed (rc={result.returncode}): {result.stderr.strip()}",
            error_code="LOOP_SSH_FAILED",
        )
    logger.info("Stopped remote loop PID=%d host=%s", state.pid, state.ssh_host)


# ---------------------------------------------------------------------------
# Liveness check
# ---------------------------------------------------------------------------


def is_loop_alive(state: LoopState) -> bool:
    """Best-effort check whether the loop process is still running.

    For local processes uses os.kill(pid, 0).  For remote processes the answer
    is optimistic (we trust our own bookkeeping) because polling via SSH on
    every status call would be too expensive.
    """
    if state.is_remote:
        return True  # assume alive; stop() will handle the gone case

    try:
        os.kill(state.pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # process exists but owned by another user
