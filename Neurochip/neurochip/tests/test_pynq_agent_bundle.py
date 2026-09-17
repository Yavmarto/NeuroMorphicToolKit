import json
import subprocess
from pathlib import Path
from unittest import mock

from neurochip.provisioning.pynq_agent_bundle import build_pynq_agent_bundle, ensure_agent_wheel
from neurochip.provisioning.pynq_agent_launch import (
    build_pynq_user_space_agent_launch_command,
)


def test_build_pynq_user_space_agent_launch_command_prefers_setsid_and_falls_back_to_nohup() -> (
    None
):
    command = build_pynq_user_space_agent_launch_command(
        agent_executable="/opt/neurochip-pynq-agent/venv/bin/neurochip-pynq-agent",
        pynq_python_path="/opt/neurochip-pynq-agent/pynq-venv/bin/python",
        install_status_path="/opt/neurochip-pynq-agent/install-status.json",
        overlay_dir="/opt/neurochip-pynq-agent/overlays",
        runtime_log_path="/opt/neurochip-pynq-agent/runtime.log",
    )

    assert "command -v setsid >/dev/null 2>&1" in command
    assert "setsid sh -c" in command
    assert "nohup sh -c" in command
    assert "NEUROCHIP_PYNQ_PYTHON=" in command
    assert "NEUROCHIP_PYNQ_INSTALL_STATUS_PATH=" in command
    assert "NEUROCHIP_PYNQ_OVERLAY_DIR=" in command


def test_build_pynq_user_space_agent_launch_command_preserves_shell_variables() -> None:
    command = build_pynq_user_space_agent_launch_command(
        agent_executable='"$AGENT_VENV_PATH/bin/neurochip-pynq-agent"',
        pynq_python_path='"$PYNQ_VENV_PATH/bin/python"',
        install_status_path='"$INSTALL_STATUS_PATH"',
        overlay_dir='"$OVERLAY_DIR"',
        runtime_log_path='"$RUNTIME_LOG_PATH"',
        shell_safe_values=True,
    )

    assert "$AGENT_VENV_PATH/bin/neurochip-pynq-agent" in command
    assert "$PYNQ_VENV_PATH/bin/python" in command
    assert "$INSTALL_STATUS_PATH" in command
    assert "$OVERLAY_DIR" in command
    assert "$RUNTIME_LOG_PATH" in command


def test_build_pynq_agent_bundle_writes_expected_files(tmp_path: Path) -> None:
    wheel_path = tmp_path / "neurochip-0.6.0-py3-none-any.whl"
    wheel_path.write_bytes(b"placeholder-wheel")

    result = build_pynq_agent_bundle(
        tmp_path / "bundle",
        overlay_version="2026.04.14",
        wheel_path=wheel_path,
    )

    bundle_dir = Path(result["bundleDir"])
    manifest = json.loads((bundle_dir / "bundle-manifest.json").read_text(encoding="utf-8"))
    install_script = (bundle_dir / "install-pynq-agent.sh").read_text(encoding="utf-8")
    systemd_unit = (bundle_dir / "systemd" / "neurochip-pynq-agent.service").read_text(
        encoding="utf-8"
    )

    assert (bundle_dir / "wheels" / wheel_path.name).exists()
    assert (bundle_dir / "requirements-pynq-agent.txt").read_text(encoding="utf-8") == "pynq>=2.7\n"
    assert manifest["overlay"]["overlayVersion"] == "2026.04.14"
    assert manifest["overlay"]["requiredFiles"] == [
        "snn_overlay.bit",
        "snn_overlay.hwh",
        "overlay_manifest.json",
    ]
    assert manifest["agentVenvPath"] == "/opt/neurochip-pynq-agent/venv"
    assert manifest["pynqVenvPath"] == "/opt/neurochip-pynq-agent/pynq-venv"
    assert "ExecStart=/opt/neurochip-pynq-agent/venv/bin/neurochip-pynq-agent" in systemd_unit
    assert (
        "Environment=NEUROCHIP_PYNQ_PYTHON=/opt/neurochip-pynq-agent/pynq-venv/bin/python"
        in systemd_unit
    )
    assert (
        "Environment=NEUROCHIP_PYNQ_OVERLAY_DIR=/opt/neurochip-pynq-agent/overlays" in systemd_unit
    )
    # XRT / BOARD env must be emitted into the unit so the worker subprocess
    # can locate libxrt_core.so.2 and pynq's EmbeddedDevice can enumerate.
    assert "Environment=XILINX_XRT=/usr" in systemd_unit
    assert "Environment=LD_LIBRARY_PATH=/usr/lib:/usr/lib:/usr/local/lib" in systemd_unit
    assert (
        "Environment=PATH=/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        in systemd_unit
    )
    assert "Environment=BOARD=Pynq-Z2" in systemd_unit
    assert wheel_path.name in install_script
    assert 'log_step "Creating Python virtual environment at $AGENT_VENV_PATH"' in install_script
    assert (
        'log_step "Creating isolated PYNQ virtual environment at $PYNQ_VENV_PATH"' in install_script
    )
    assert '"$PYNQ_VENV_PATH/bin/pip" install --upgrade pynq' in install_script
    assert 'log_step "Force-reinstalling Neurochip PYNQ agent wheel $WHEEL_NAME"' in install_script
    assert (
        '"$AGENT_VENV_PATH/bin/pip" install --force-reinstall --no-deps '
        '"$BUNDLE_DIR/wheels/$WHEEL_NAME"' in install_script
    )
    assert 'write_install_status "user-space"' in install_script
    assert "INSTALL_STATUS_JSON=" in install_script
    assert 'NEUROCHIP_PYNQ_OVERLAY_DIR="$OVERLAY_DIR"' in install_script
    assert "command -v setsid >/dev/null 2>&1" in install_script
    assert "setsid sh -c" in install_script
    assert "nohup sh -c" in install_script
    # Health wait must be wide enough for a cold ARM provision (ARM pip
    # compile + uvicorn cold-start + systemctl restart routinely >30s).
    assert "deadline = time.time() + 120.0" in install_script
    # Canonical PYNQ runtime detection: prefer the board's stock pynq-venv when
    # present so the agent does not have to re-pip-install pynq without the
    # Xilinx-specific pyxrt bindings.
    assert (
        'CANONICAL_PYNQ_PYTHON="${CANONICAL_PYNQ_PYTHON:-/usr/local/share/pynq-venv/bin/python}"'
        in install_script
    )
    assert "detect_pynq_runtime() {" in install_script
    assert "import pynq; import pyxrt" in install_script
    assert 'PYNQ_RUNTIME_SOURCE="canonical"' in install_script
    assert 'PYNQ_RUNTIME_SOURCE="isolated"' in install_script
    assert "if detect_pynq_runtime; then" in install_script
    # The systemd unit must be rewritten so NEUROCHIP_PYNQ_PYTHON points at the
    # effective interpreter (canonical or isolated) rather than the bundled
    # default.
    assert (
        'sed "s|^Environment=NEUROCHIP_PYNQ_PYTHON=.*|Environment=NEUROCHIP_PYNQ_PYTHON=$EFFECTIVE_PYNQ_PYTHON|"'
        in install_script
    )
    # The user-space launch must also use the effective interpreter rather
    # than the bundled default PYNQ venv python.
    assert 'NEUROCHIP_PYNQ_PYTHON="$EFFECTIVE_PYNQ_PYTHON"' in install_script
    assert 'EFFECTIVE_PYNQ_PYTHON="$PYNQ_VENV_PATH/bin/python"' in install_script
    # install-status.json should now carry the effective interpreter and its
    # source so operator surfaces can surface it.
    assert '"effectivePynqPython": sys.argv[7]' in install_script
    assert '"pynqRuntimeSource": sys.argv[8]' in install_script
    assert '"agentPackageVersion": sys.argv[9]' in install_script
    assert '"agentWheelName": sys.argv[10]' in install_script
    assert 'AGENT_PACKAGE_VERSION="$(' in install_script
    assert 'print(metadata.version("neurochip"))' in install_script


def test_ensure_agent_wheel_rebuilds_even_when_dist_contains_existing_wheel(tmp_path: Path) -> None:
    dist_dir = tmp_path / "dist"
    dist_dir.mkdir(parents=True, exist_ok=True)
    stale_wheel = dist_dir / "neurochip-0.6.0-py3-none-any.whl"
    stale_wheel.write_bytes(b"stale")

    def _fake_build(*args, **kwargs):
        stale_wheel.write_bytes(b"fresh")
        return subprocess.CompletedProcess(args=args[0], returncode=0, stdout="", stderr="")

    with mock.patch(
        "neurochip.provisioning.pynq_agent_bundle.subprocess.run",
        side_effect=_fake_build,
    ) as run_mock:
        resolved = ensure_agent_wheel(tmp_path)

    run_mock.assert_called_once()
    assert resolved == stale_wheel
    assert stale_wheel.read_bytes() == b"fresh"
