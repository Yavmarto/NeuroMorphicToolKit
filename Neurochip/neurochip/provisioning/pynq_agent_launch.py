"""Shared launch helpers for the board-side PYNQ agent."""

from __future__ import annotations

import shlex


def _shell_value(value: str, *, shell_safe_values: bool) -> str:
    return value if shell_safe_values else shlex.quote(value)


def build_pynq_agent_match_pattern(agent_executable: str) -> str:
    """Return a ``pkill -f``/``pgrep -f`` pattern that cannot match its own carrier.

    ``-f`` matches whole command lines, so a pattern sent inline over SSH alongside the
    command that restarts the agent matches the remote shell too, and the stop step
    kills the process that was about to do the restart. Bracketing the first character
    of the executable name keeps the regex matching the real process while the literal
    ``…/[n]eurochip-pynq-agent`` in a carrier's argv does not match it. Executables
    written as shell expressions are returned unchanged.
    """
    head, separator, name = agent_executable.rpartition("/")
    if not name or not name[0].isalnum():
        return agent_executable
    return f"{head}{separator}[{name[0]}]{name[1:]}"


def build_pynq_agent_stop_command(
    *,
    agent_executable: str,
    shell_safe_values: bool = False,
) -> str:
    """Build the shell command that stops a running user-space PYNQ agent."""
    pattern = _shell_value(
        build_pynq_agent_match_pattern(agent_executable),
        shell_safe_values=shell_safe_values,
    )
    return f"pkill -f {pattern} >/dev/null 2>&1 || true"


def build_pynq_user_space_agent_launch_command(
    *,
    agent_executable: str,
    pynq_python_path: str,
    install_status_path: str,
    overlay_dir: str,
    runtime_log_path: str,
    shell_safe_values: bool = False,
) -> str:
    """Build a durable shell command for launching the PYNQ agent in user space.

    When ``shell_safe_values`` is ``False`` the inputs are treated as literal values
    and shell-escaped. When ``True`` the inputs are treated as already-safe shell
    expressions, which lets generated install scripts pass variables such as
    ``"$AGENT_VENV_PATH/bin/neurochip-pynq-agent"`` without double quoting.
    """

    env_assignments = " ".join(
        [
            f"NEUROCHIP_PYNQ_PYTHON={_shell_value(pynq_python_path, shell_safe_values=shell_safe_values)}",
            'NEUROCHIP_PYNQ_INSTALL_MODE="user-space"',
            f"NEUROCHIP_PYNQ_INSTALL_STATUS_PATH={_shell_value(install_status_path, shell_safe_values=shell_safe_values)}",
            f"NEUROCHIP_PYNQ_OVERLAY_DIR={_shell_value(overlay_dir, shell_safe_values=shell_safe_values)}",
        ]
    )
    executable = _shell_value(agent_executable, shell_safe_values=shell_safe_values)
    runtime_log = _shell_value(runtime_log_path, shell_safe_values=shell_safe_values)
    launch_payload = f"exec env {env_assignments} {executable} >{runtime_log} 2>&1 </dev/null"
    quoted_payload = shlex.quote(launch_payload)
    return (
        "if command -v setsid >/dev/null 2>&1; then "
        f"setsid sh -c {quoted_payload} >/dev/null 2>&1 & "
        "else "
        f"nohup sh -c {quoted_payload} >/dev/null 2>&1 & "
        "fi"
    )
