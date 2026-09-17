"""A damaged image download must be retried, not turned into a dead end.

Layers arrive over the network and can land corrupt ("crc32 mismatch") even when
the published blob is intact. The end user has no terminal to pull again by hand,
so the installer has to do it. These tests run the real ``install.sh`` against a
fake container engine instead of asserting on its source text.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
INSTALL_SCRIPT = (
    ROOT / "nmtk" / "neuro_toolkit" / "assets" / "deployment" / "install.sh"
)
STACK_SCRIPT = INSTALL_SCRIPT.with_name("nmtk-stack.sh")

CORRUPT_LAYER_ERROR = (
    "unable to copy from source docker://ghcr.io/example/snn-mlir-compiler:latest: "
    'writing blob: adding layer with blob "sha256:24dba2149b7b": unpacking failed '
    "(error: pigz: skipping: <stdin>: corrupted -- crc32 mismatch: exit status 1)"
)


def _write_executable(directory: Path, name: str, body: str) -> None:
    path = directory / name
    path.write_text(body)
    path.chmod(0o755)


def _fake_engine(bin_dir: Path, *, failing_pulls: int) -> None:
    """A container engine that succeeds at everything except the first N pulls."""
    body = f"""#!/usr/bin/env bash
printf '%s\\n' "$*" >>"$NMTK_FAKE_LOG"
for argument in "$@"; do
  if [ "$argument" = "pull" ]; then
    attempts_file="$NMTK_FAKE_STATE/pull-attempts"
    printf 'x' >>"$attempts_file"
    attempts="$(wc -c <"$attempts_file" | tr -d ' ')"
    if [ "$attempts" -le {failing_pulls} ]; then
      printf '%s\\n' {CORRUPT_LAYER_ERROR!r} >&2
      exit 1
    fi
    exit 0
  fi
done
exit 0
"""
    for name in ("docker", "podman"):
        _write_executable(bin_dir, name, body)


def _run_install(
    tmp_path: Path, *, failing_pulls: int
) -> tuple[subprocess.CompletedProcess[str], str, str, str]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    state = tmp_path / "state"
    state.mkdir()
    workdir = tmp_path / "deploy"
    workdir.mkdir()
    shutil.copy(INSTALL_SCRIPT, workdir / "install.sh")
    shutil.copy(STACK_SCRIPT, workdir / "nmtk-stack.sh")
    home = tmp_path / "home"
    home.mkdir()

    _fake_engine(bin_dir, failing_pulls=failing_pulls)
    # The health probes and the GNU timeout wrapper are not what these tests are
    # about, so they always succeed.
    # install.sh reads a status code back from its authenticated launcher
    # check, so the stand-in has to honour --write-out rather than just
    # succeeding silently.
    _write_executable(
        bin_dir,
        "curl",
        "#!/usr/bin/env bash\n"
        'for arg in "$@"; do\n'
        '  case "$arg" in\n'
        "    --write-out|-w) echo 200; exit 0 ;;\n"
        "  esac\n"
        "done\n"
        "exit 0\n",
    )
    _write_executable(bin_dir, "systemctl", "#!/usr/bin/env bash\nexit 0\n")
    _write_executable(
        bin_dir,
        "timeout",
        "#!/usr/bin/env bash\n"
        'while [[ "$1" == --* ]]; do shift; done\n'
        "shift\n"
        'exec "$@"\n',
    )

    status_file = workdir / "deployment.status"
    log_file = workdir / "deployment.log"
    result = subprocess.run(
        [
            "bash",
            "install.sh",
            "podman",
            "9000",
            "latest",
            "false",
            "127.0.0.1",
            str(status_file),
            str(log_file),
        ],
        cwd=workdir,
        capture_output=True,
        text=True,
        env={
            **os.environ,
            "PATH": f"{bin_dir}:/usr/bin:/bin",
            "NMTK_FAKE_LOG": str(state / "commands.log"),
            "NMTK_FAKE_STATE": str(state),
            "NMTK_DEPLOY_PULL_RETRY_DELAY": "0",
            "HOME": str(home),
        },
        timeout=300,
        check=False,
    )
    return (
        result,
        status_file.read_text() if status_file.is_file() else "",
        log_file.read_text() if log_file.is_file() else "",
        (state / "commands.log").read_text()
        if (state / "commands.log").is_file()
        else "",
    )


@pytest.mark.parametrize("failing_pulls", [1, 2])
def test_a_damaged_image_download_is_retried_until_it_succeeds(
    tmp_path: Path, failing_pulls: int
) -> None:
    result, status, log, commands = _run_install(tmp_path, failing_pulls=failing_pulls)

    assert result.returncode == 0, f"{status}\n{log}\n{result.stderr}"
    assert status.startswith("completed|100|"), status
    assert commands.count(" pull") == failing_pulls + 1, commands
    assert "Image download attempt 1 of 3 failed; retrying." in log


def test_a_download_that_keeps_failing_reports_how_many_attempts_it_made(
    tmp_path: Path,
) -> None:
    result, status, log, commands = _run_install(tmp_path, failing_pulls=99)

    assert result.returncode == 1
    assert status.startswith("failed|100|"), status
    assert "could not be downloaded after 3 attempts" in status
    # It really tried three times rather than reporting a number it never used.
    assert commands.count(" pull") == 3, commands
    assert "Deployment failed" not in status
    assert "diagnostics were captured" in status
    assert "crc32 mismatch" in log
