"""Launcher-owned provisioning bundle helpers.

These helpers intentionally mirror the minimal Neurochip remote-install
artifacts the launcher needs so launcher runtime behavior does not depend on
importing or loading checked-out Neurochip package internals.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import stat
import subprocess
from pathlib import Path
from typing import Any

from .provisioning_templates import render_provisioning_template
from .runtime_artifact import inspect_neurochip_runtime_artifact

# These module-level constants are secondary fallbacks for callers that invoke
# build_pynq_agent_bundle() or build_akida_host_bundle() directly without passing
# manifest-owned values.  Within the normal launcher server flow, server.py always
# derives these values from the typed NeurochipLauncherRuntimeContract loaded from
# modules.json before calling the bundle helpers, so these constants are never hit
# on the hot path.  Do not treat them as authoritative defaults for new code;
# use _load_neurochip_launcher_runtime_contract() from server.py instead.
DEFAULT_REMOTE_INSTALL_ROOT = "/opt/neurochip-pynq-agent"
DEFAULT_REMOTE_VENV_PATH = f"{DEFAULT_REMOTE_INSTALL_ROOT}/venv"
DEFAULT_REMOTE_PYNQ_VENV_PATH = f"{DEFAULT_REMOTE_INSTALL_ROOT}/pynq-venv"
DEFAULT_REMOTE_OVERLAY_DIR = f"{DEFAULT_REMOTE_INSTALL_ROOT}/overlays"
DEFAULT_REMOTE_SERVICE_NAME = "neurochip-pynq-agent"
DEFAULT_CANONICAL_PYNQ_PYTHON = "/usr/local/share/pynq-venv/bin/python"
DEFAULT_XILINX_XRT_PATH = "/usr"
DEFAULT_BOARD_NAME = "Pynq-Z2"
DEFAULT_AGENT_HEALTH_TIMEOUT_S = 120

DEFAULT_AKIDA_INSTALL_ROOT = "/opt/neurochip-akida-host"
DEFAULT_AKIDA_SERVICE_USER = "neurochip"
DEFAULT_AKIDA_VENV_PATH = f"{DEFAULT_AKIDA_INSTALL_ROOT}/venv"
DEFAULT_AKIDA_RUNTIME_SERVICE = "neurochip"
DEFAULT_AKIDA_CONTROL_SERVICE = "neurochip-akida-control"
DEFAULT_AKIDA_RUNTIME_PORT = 8002
DEFAULT_AKIDA_CONTROL_PORT = 8091
DEFAULT_AKIDA_TOKEN_PATH = f"{DEFAULT_AKIDA_INSTALL_ROOT}/credentials/api-token"
DEFAULT_AKIDA_INSTALL_STATUS_PATH = f"{DEFAULT_AKIDA_INSTALL_ROOT}/install-status.json"
# The BrainChip SDK publishes wheels for CPython 3.10-3.12 only, and TensorFlow
# ships none at all for 3.13+. Mirrors `akidaRuntime.pythonRange` in
# nmtk/neuro_toolkit/assets/modules.json, which stays the source of truth.
DEFAULT_AKIDA_PYTHON_MIN = (3, 10)
DEFAULT_AKIDA_PYTHON_MAX = (3, 13)
DEFAULT_AKIDA_PYTHON_RANGE = ">=3.10,<3.13"


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _latest_wheel(dist_dir: Path) -> Path | None:
    wheels = sorted(
        dist_dir.glob("neurochip-*.whl"),
        key=lambda path: path.stat().st_mtime,
    )
    return wheels[-1] if wheels else None


def ensure_agent_wheel(repo_root: Path | None = None) -> Path:
    """Locate or build the latest Neurochip wheel for provisioning."""
    root = repo_root or _repo_root()
    dist_dir = root / "dist"

    result = subprocess.run(
        ["poetry", "build", "-f", "wheel"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            result.stderr.strip() or result.stdout.strip() or "poetry build failed"
        )

    wheel = _latest_wheel(dist_dir)
    if wheel is None:
        raise RuntimeError("poetry build completed without producing a wheel")
    return wheel


def _shell_value(value: str, *, shell_safe_values: bool) -> str:
    return value if shell_safe_values else shlex.quote(value)


def build_pynq_agent_match_pattern(agent_executable: str) -> str:
    """Return a ``pkill -f``/``pgrep -f`` pattern that cannot match its own carrier.

    ``-f`` matches whole command lines, so when the pattern travels inside the very
    command line that runs it — an inline ``ssh host 'pkill -f /path/agent; … start …'``
    — it matches the remote shell as well as the agent, and the stop step kills the
    process that was about to do the restart. Bracketing the first character of the
    executable name keeps the regex matching the real process (whose command line is
    ``…/neurochip-pynq-agent``) while the literal ``…/[n]eurochip-pynq-agent`` sitting in
    a carrier's argv does not match it.

    Executables written as shell expressions (the install-script call sites, where the
    pattern lives in a file and never appears in a command line) are returned unchanged.
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
    xilinx_xrt_path: str = DEFAULT_XILINX_XRT_PATH,
    board_name: str = DEFAULT_BOARD_NAME,
) -> str:
    """Build a durable shell command for launching the PYNQ agent in user space."""
    env_assignments = " ".join(
        [
            f"NEUROCHIP_PYNQ_PYTHON={_shell_value(pynq_python_path, shell_safe_values=shell_safe_values)}",
            'NEUROCHIP_PYNQ_INSTALL_MODE="user-space"',
            f"NEUROCHIP_PYNQ_INSTALL_STATUS_PATH={_shell_value(install_status_path, shell_safe_values=shell_safe_values)}",
            f"NEUROCHIP_PYNQ_OVERLAY_DIR={_shell_value(overlay_dir, shell_safe_values=shell_safe_values)}",
            # The same XRT environment the systemd unit injects. The stock image
            # sets these in /etc/profile.d/xrt_setup.sh, which a detached
            # `setsid sh -c` never sources — without them pynq reports "No devices
            # found, is the XRT environment sourced?" and enumerates nothing, so a
            # user-space agent could never see the board it is running on.
            f"XILINX_XRT={xilinx_xrt_path}",
            f"LD_LIBRARY_PATH={xilinx_xrt_path}/lib:/usr/lib:/usr/local/lib",
            f"BOARD={board_name}",
        ]
    )
    executable = _shell_value(agent_executable, shell_safe_values=shell_safe_values)
    runtime_log = _shell_value(runtime_log_path, shell_safe_values=shell_safe_values)
    launch_payload = (
        f"exec env {env_assignments} {executable} >{runtime_log} 2>&1 </dev/null"
    )
    quoted_payload = shlex.quote(launch_payload)
    return (
        "if command -v setsid >/dev/null 2>&1; then "
        f"setsid sh -c {quoted_payload} >/dev/null 2>&1 & "
        "else "
        f"nohup sh -c {quoted_payload} >/dev/null 2>&1 & "
        "fi"
    )


def _pynq_systemd_unit_text(
    *,
    service_name: str,
    install_root: str,
    agent_venv_path: str,
    agent_executable_name: str,
    pynq_python_path: str,
    install_status_path: str,
    overlay_dir: str,
    xilinx_xrt_path: str = DEFAULT_XILINX_XRT_PATH,
    board_name: str = DEFAULT_BOARD_NAME,
) -> str:
    return render_provisioning_template(
        "pynq/v1/neurochip-pynq-agent.service.tmpl",
        {
            "INSTALL_ROOT": install_root,
            "AGENT_VENV_PATH": agent_venv_path,
            "AGENT_EXECUTABLE_NAME": agent_executable_name,
            "PYNQ_PYTHON_PATH": pynq_python_path,
            "INSTALL_STATUS_PATH": install_status_path,
            "OVERLAY_DIR": overlay_dir,
            "XILINX_XRT_PATH": xilinx_xrt_path,
            "BOARD_NAME": board_name,
        },
    )


def _pynq_install_script_text(
    *,
    install_root: str,
    agent_venv_path: str,
    pynq_venv_path: str,
    overlay_dir: str,
    service_name: str,
    agent_executable_name: str,
    install_status_path: str,
    runtime_log_path: str,
    wheel_name: str,
) -> str:
    stop_command = build_pynq_agent_stop_command(
        agent_executable='"$AGENT_VENV_PATH/bin/$AGENT_EXECUTABLE_NAME"',
        shell_safe_values=True,
    )
    launch_command = build_pynq_user_space_agent_launch_command(
        agent_executable='"$AGENT_VENV_PATH/bin/$AGENT_EXECUTABLE_NAME"',
        pynq_python_path='"$EFFECTIVE_PYNQ_PYTHON"',
        install_status_path='"$INSTALL_STATUS_PATH"',
        overlay_dir='"$OVERLAY_DIR"',
        runtime_log_path='"$RUNTIME_LOG_PATH"',
        shell_safe_values=True,
    )
    return render_provisioning_template(
        "pynq/v1/install-pynq-agent.sh.tmpl",
        {
            "INSTALL_ROOT": install_root,
            "AGENT_VENV_PATH": agent_venv_path,
            "PYNQ_VENV_PATH": pynq_venv_path,
            "OVERLAY_DIR": overlay_dir,
            "SERVICE_NAME": service_name,
            "AGENT_EXECUTABLE_NAME": agent_executable_name,
            "WHEEL_NAME": wheel_name,
            "INSTALL_STATUS_PATH": install_status_path,
            "RUNTIME_LOG_PATH": runtime_log_path,
            "STOP_COMMAND": stop_command,
            "LAUNCH_COMMAND": launch_command,
        },
    )


def _overlay_manifest(
    *,
    overlay_version: str,
    overlay_dir: str,
    agent_runtime: str,
) -> dict[str, Any]:
    return {
        "overlayVersion": overlay_version,
        "overlayDirectory": overlay_dir,
        "requiredFiles": [
            "snn_overlay.bit",
            "snn_overlay.hwh",
            "overlay_manifest.json",
        ],
        "agentRuntime": agent_runtime,
    }


def build_pynq_agent_bundle(
    output_dir: Path,
    *,
    overlay_version: str = "dev",
    repo_root: Path | None = None,
    wheel_path: Path | None = None,
    install_root: str = DEFAULT_REMOTE_INSTALL_ROOT,
    agent_venv_path: str = DEFAULT_REMOTE_VENV_PATH,
    pynq_venv_path: str = DEFAULT_REMOTE_PYNQ_VENV_PATH,
    overlay_dir: str = DEFAULT_REMOTE_OVERLAY_DIR,
    service_name: str = DEFAULT_REMOTE_SERVICE_NAME,
    agent_executable_name: str = DEFAULT_REMOTE_SERVICE_NAME,
    install_status_path: str | None = None,
    runtime_log_path: str | None = None,
) -> dict[str, Any]:
    """Build a local bundle of files needed for remote PYNQ provisioning."""
    root = repo_root or _repo_root()
    bundle_dir = output_dir.resolve()
    wheel = (wheel_path or ensure_agent_wheel(root)).resolve()
    resolved_install_status_path = (
        install_status_path or f"{install_root}/install-status.json"
    )
    resolved_runtime_log_path = runtime_log_path or f"{install_root}/runtime.log"

    wheels_dir = bundle_dir / "wheels"
    systemd_dir = bundle_dir / "systemd"
    overlays_dir = bundle_dir / "overlays"
    for directory in (wheels_dir, systemd_dir, overlays_dir):
        directory.mkdir(parents=True, exist_ok=True)

    copied_wheel = wheels_dir / wheel.name
    shutil.copy2(wheel, copied_wheel)

    manifest = _overlay_manifest(
        overlay_version=overlay_version,
        overlay_dir=overlay_dir,
        agent_runtime=agent_executable_name,
    )
    (bundle_dir / "bundle-manifest.json").write_text(
        json.dumps(
            {
                "serviceName": service_name,
                "installRoot": install_root,
                "venvPath": agent_venv_path,
                "agentVenvPath": agent_venv_path,
                "pynqVenvPath": pynq_venv_path,
                "installStatusPath": resolved_install_status_path,
                "runtimeLogPath": resolved_runtime_log_path,
                "overlay": manifest,
                "wheel": copied_wheel.name,
            },
            indent=2,
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    (bundle_dir / "requirements-pynq-agent.txt").write_text(
        "pynq>=2.7\n",
        encoding="utf-8",
    )
    (systemd_dir / f"{service_name}.service").write_text(
        _pynq_systemd_unit_text(
            service_name=service_name,
            install_root=install_root,
            agent_venv_path=agent_venv_path,
            agent_executable_name=agent_executable_name,
            pynq_python_path=f"{pynq_venv_path}/bin/python",
            install_status_path=resolved_install_status_path,
            overlay_dir=overlay_dir,
        ),
        encoding="utf-8",
    )
    install_script = bundle_dir / "install-pynq-agent.sh"
    install_script.write_text(
        _pynq_install_script_text(
            install_root=install_root,
            agent_venv_path=agent_venv_path,
            pynq_venv_path=pynq_venv_path,
            overlay_dir=overlay_dir,
            service_name=service_name,
            agent_executable_name=agent_executable_name,
            install_status_path=resolved_install_status_path,
            runtime_log_path=resolved_runtime_log_path,
            wheel_name=copied_wheel.name,
        ),
        encoding="utf-8",
    )
    install_script.chmod(install_script.stat().st_mode | stat.S_IXUSR)
    (overlays_dir / "pynq_overlay_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    (bundle_dir / "README.md").write_text(
        "\n".join(
            [
                "# NeuroChip PYNQ Agent Bundle",
                "",
                "This bundle is uploaded by the launcher control service to provision a stock PYNQ image.",
                "",
                "Contents:",
                f"- wheels/{copied_wheel.name}",
                "- systemd/neurochip-pynq-agent.service",
                "- install-pynq-agent.sh",
                "- overlays/pynq_overlay_manifest.json",
                "",
            ]
        ),
        encoding="utf-8",
    )
    return {
        "bundleDir": str(bundle_dir),
        "wheelName": copied_wheel.name,
        "overlayManifest": manifest,
        "serviceName": service_name,
        "installRoot": install_root,
        "venvPath": agent_venv_path,
        "agentVenvPath": agent_venv_path,
        "pynqVenvPath": pynq_venv_path,
        "overlayDir": overlay_dir,
        "installStatusPath": resolved_install_status_path,
        "runtimeLogPath": resolved_runtime_log_path,
    }


def _akida_runtime_unit_text(
    *,
    install_root: str,
    venv_path: str,
    service_user: str,
    runtime_service_name: str,
    runtime_port: int,
) -> str:
    return render_provisioning_template(
        "akida/v1/neurochip-akida-runtime.service.tmpl",
        {
            "INSTALL_ROOT": install_root,
            "VENV_PATH": venv_path,
            "SERVICE_USER": service_user,
            "RUNTIME_SERVICE_NAME": runtime_service_name,
            "RUNTIME_PORT": str(runtime_port),
        },
    )


def _akida_control_unit_text(
    *,
    install_root: str,
    venv_path: str,
    service_user: str,
    control_service_name: str,
) -> str:
    return render_provisioning_template(
        "akida/v1/neurochip-akida-control.service.tmpl",
        {
            "INSTALL_ROOT": install_root,
            "VENV_PATH": venv_path,
            "SERVICE_USER": service_user,
            "CONTROL_SERVICE_NAME": control_service_name,
        },
    )


def _remote_control_script_text() -> str:
    return render_provisioning_template(
        "akida/v1/akida_remote_control_service.py.tmpl", {}
    )


def _parse_python_range(python_range: str) -> tuple[tuple[int, int], tuple[int, int]]:
    """Turn a manifest `pythonRange` like ``>=3.10,<3.13`` into inclusive/exclusive bounds.

    Parsed here rather than in bash so the generated script only ever asks a
    candidate interpreter about itself, which is exact. Anything unparseable
    falls back to the documented Akida range instead of failing the build — a
    malformed manifest must not make provisioning impossible.
    """
    minimum = DEFAULT_AKIDA_PYTHON_MIN
    maximum = DEFAULT_AKIDA_PYTHON_MAX
    for clause in str(python_range or "").split(","):
        clause = clause.strip()
        match = re.match(r"^(>=|<)\s*(\d+)\.(\d+)", clause)
        if not match:
            continue
        operator, major, minor = (
            match.group(1),
            int(match.group(2)),
            int(match.group(3)),
        )
        if operator == ">=":
            minimum = (major, minor)
        else:
            maximum = (major, minor)
    return minimum, maximum


def _akida_install_script_text(
    *,
    install_root: str,
    service_user: str,
    venv_path: str,
    runtime_service_name: str,
    control_service_name: str,
    runtime_port: int,
    control_port: int,
    token_path: str,
    install_status_path: str,
    wheel_name: str,
    artifact_version: str,
    artifact_sha256: str,
    required_packages: list[str],
    python_range: str = DEFAULT_AKIDA_PYTHON_RANGE,
    standalone_python: dict[str, Any] | None = None,
) -> str:
    package_install = " ".join(shlex.quote(package) for package in required_packages)
    python_min, python_max = _parse_python_range(python_range)
    range_label = f">={python_min[0]}.{python_min[1]},<{python_max[0]}.{python_max[1]}"
    standalone = standalone_python or {}
    standalone_version = str(standalone.get("version") or "").strip()
    standalone_url = str(standalone.get("url") or "").strip()
    standalone_sha256 = str(standalone.get("sha256") or "").strip()
    standalone_arch = str(standalone.get("architecture") or "x86_64").strip()
    # Asked of the interpreter itself -- no version parsing in shell.
    version_probe = (
        f"import sys; sys.exit(0 if {python_min} <= sys.version_info[:2] < "
        f"{python_max} else 1)"
    )

    # The two blocks below are conditional on whether any Akida runtime
    # packages are declared. render_provisioning_template does flat
    # `@@TOKEN@@` substitution with no template-language conditionals, so
    # each block is pre-built here as a single string (leading "\n", no
    # trailing newline) and attached to the end of the preceding template
    # line; substituting "" collapses it to nothing, exactly matching the
    # original `*(...) if package_install else []` list-splice behavior.
    package_install_function = (
        (
            "\n"
            + "\n".join(
                [
                    "install_akida_packages() {",
                    f"  if akida_pip install {package_install}; then",
                    "    return",
                    "  fi",
                    '  log_step "Package install failed; discarding the download cache and fetching again"',
                    "  akida_pip cache purge || true",
                    f"  if akida_pip install --no-cache-dir {package_install}; then",
                    "    return",
                    "  fi",
                    '  fail_install "The Akida SDK could not be downloaded onto this server. The files kept arriving damaged or incomplete, even after a clean retry. Check this server\'s internet connection, then run setup again."',
                    "}",
                ]
            )
        )
        if package_install
        else ""
    )
    install_packages_call = (
        '\n  log_step "Installing Akida runtime dependencies"\n  install_akida_packages'
        if package_install
        else ""
    )

    return render_provisioning_template(
        "akida/v1/install-akida-host.sh.tmpl",
        {
            "INSTALL_ROOT": install_root,
            "SERVICE_USER": service_user,
            "VENV_PATH": venv_path,
            "RUNTIME_SERVICE_NAME": runtime_service_name,
            "CONTROL_SERVICE_NAME": control_service_name,
            "RUNTIME_PORT": str(runtime_port),
            "CONTROL_PORT": str(control_port),
            "TOKEN_PATH": token_path,
            "INSTALL_STATUS_PATH": install_status_path,
            "WHEEL_NAME": wheel_name,
            "ARTIFACT_VERSION": artifact_version,
            "ARTIFACT_SHA256": artifact_sha256,
            "RANGE_LABEL": range_label,
            "STANDALONE_VERSION": standalone_version,
            "STANDALONE_URL": standalone_url,
            "STANDALONE_SHA256": standalone_sha256,
            "STANDALONE_ARCH": standalone_arch,
            "VERSION_PROBE_QUOTED": shlex.quote(version_probe),
            "PACKAGE_INSTALL_FUNCTION": package_install_function,
            "INSTALL_PACKAGES_CALL": install_packages_call,
        },
    )


def build_akida_host_bundle(
    bundle_dir: Path,
    *,
    repo_root: Path,
    required_packages: list[str],
    wheel_path: Path | None = None,
    install_root: str = DEFAULT_AKIDA_INSTALL_ROOT,
    service_user: str = DEFAULT_AKIDA_SERVICE_USER,
    venv_path: str = DEFAULT_AKIDA_VENV_PATH,
    runtime_service_name: str = DEFAULT_AKIDA_RUNTIME_SERVICE,
    control_service_name: str = DEFAULT_AKIDA_CONTROL_SERVICE,
    runtime_port: int = DEFAULT_AKIDA_RUNTIME_PORT,
    control_port: int = DEFAULT_AKIDA_CONTROL_PORT,
    token_path: str = DEFAULT_AKIDA_TOKEN_PATH,
    install_status_path: str = DEFAULT_AKIDA_INSTALL_STATUS_PATH,
    python_range: str = DEFAULT_AKIDA_PYTHON_RANGE,
    standalone_python: dict[str, Any] | None = None,
) -> dict[str, Any]:
    bundle_dir.mkdir(parents=True, exist_ok=True)
    wheels_dir = bundle_dir / "wheels"
    systemd_dir = bundle_dir / "systemd"
    bin_dir = bundle_dir / "bin"
    wheels_dir.mkdir(parents=True, exist_ok=True)
    systemd_dir.mkdir(parents=True, exist_ok=True)
    bin_dir.mkdir(parents=True, exist_ok=True)

    resolved_wheel_path = wheel_path or ensure_agent_wheel(repo_root)
    artifact = inspect_neurochip_runtime_artifact(resolved_wheel_path)
    copied_wheel = wheels_dir / artifact.wheel_path.name
    shutil.copy2(artifact.wheel_path, copied_wheel)

    active_venv_path = f"{install_root.rstrip('/')}/current"
    runtime_unit = systemd_dir / f"{runtime_service_name}.service"
    runtime_unit.write_text(
        _akida_runtime_unit_text(
            install_root=install_root,
            venv_path=active_venv_path,
            service_user=service_user,
            runtime_service_name=runtime_service_name,
            runtime_port=runtime_port,
        ),
        encoding="utf-8",
    )

    control_unit = systemd_dir / f"{control_service_name}.service"
    control_unit.write_text(
        _akida_control_unit_text(
            install_root=install_root,
            venv_path=active_venv_path,
            service_user=service_user,
            control_service_name=control_service_name,
        ),
        encoding="utf-8",
    )

    control_script = bin_dir / "akida_remote_control_service.py"
    control_script.write_text(_remote_control_script_text(), encoding="utf-8")
    control_script.chmod(control_script.stat().st_mode | stat.S_IXUSR)

    install_script = bundle_dir / "install-akida-host.sh"
    install_script.write_text(
        _akida_install_script_text(
            install_root=install_root,
            service_user=service_user,
            venv_path=venv_path,
            runtime_service_name=runtime_service_name,
            control_service_name=control_service_name,
            runtime_port=runtime_port,
            control_port=control_port,
            token_path=token_path,
            install_status_path=install_status_path,
            wheel_name=copied_wheel.name,
            artifact_version=artifact.version,
            artifact_sha256=artifact.sha256,
            required_packages=required_packages,
            python_range=python_range,
            standalone_python=standalone_python,
        ),
        encoding="utf-8",
    )
    install_script.chmod(install_script.stat().st_mode | stat.S_IXUSR)

    manifest = {
        "installRoot": install_root,
        "serviceUser": service_user,
        "venvPath": active_venv_path,
        "runtimeServiceName": runtime_service_name,
        "controlServiceName": control_service_name,
        "runtimePort": runtime_port,
        "controlPort": control_port,
        "requiredPackages": required_packages,
        "artifactVersion": artifact.version,
        "artifactSha256": artifact.sha256,
        "tokenPath": token_path,
        "installStatusPath": install_status_path,
        "bundleContents": [
            os.path.relpath(copied_wheel, bundle_dir),
            os.path.relpath(runtime_unit, bundle_dir),
            os.path.relpath(control_unit, bundle_dir),
            os.path.relpath(control_script, bundle_dir),
            os.path.relpath(install_script, bundle_dir),
        ],
    }
    (bundle_dir / "bundle-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    return manifest
