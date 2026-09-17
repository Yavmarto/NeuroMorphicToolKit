"""A failed backend update must restore the last-good images, unless data moved.

The app deploys by a tag that used to be the mutable ``:latest``. A bad release
therefore used to leave every updating host down until another good release
shipped, because ``install.sh`` had no restore path. These tests run the real
``install.sh`` against a fake container engine: the new release never becomes
healthy, and the installer must put the previous images back — except when the
release carries a schema or data migration, which the CTO ruled must hold for a
human instead of silently reverting migrated data.
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

SUITE_API = "ghcr.io/completed-spoon-6/neuromorphictoolkit/suite-api"
LAUNCHER = "ghcr.io/completed-spoon-6/neuromorphictoolkit/launcher-control"
GOOD_DIGEST = "sha256:" + "1" * 64

FAKE_ENGINE = """#!/usr/bin/env bash
printf '%s\\n' "$*" >>"$NMTK_FAKE_LOG"
first="$1"
if [ "$first" = "image" ] && [ "${2:-}" = "inspect" ]; then
  printf '%s\\n' "${NMTK_FAKE_VERSION:-2.0.0}"
  exit 0
fi
if [ "$first" = "inspect" ]; then
  printf 'image|%s:%s|sha256:aaaa|%s@%s\\n' "$NMTK_FAKE_SUITE_API" "$NMTK_FAKE_GOOD_TAG" "$NMTK_FAKE_SUITE_API" "$NMTK_FAKE_GOOD_DIGEST"
  printf 'image|%s:%s|sha256:bbbb|%s@%s\\n' "$NMTK_FAKE_LAUNCHER" "$NMTK_FAKE_GOOD_TAG" "$NMTK_FAKE_LAUNCHER" "$NMTK_FAKE_GOOD_DIGEST"
  exit 0
fi
case " $* " in
  *" ps -q "*)
    printf 'cid-suite-api\\ncid-launcher\\n'
    ;;
  *" up "*)
    printf '%s' "${NMTK_IMAGE_TAG:-}" >"$NMTK_FAKE_STATE/current-tag"
    ;;
esac
exit 0
"""

# Serves both the health probes and the pre-update version probe. When the
# running tag is the bad release, the health endpoints fail the way the real
# backend would while the new image is broken.
FAKE_CURL = """#!/usr/bin/env bash
for argument in "$@"; do
  case "$argument" in
    --write-out|-w) printf '200'; exit 0 ;;
  esac
done
url=""
for argument in "$@"; do
  case "$argument" in
    http*) url="$argument" ;;
  esac
done
current="$(cat "$NMTK_FAKE_STATE/current-tag" 2>/dev/null)"
case "$url" in
  *"/health"*)
    if [ -n "$NMTK_FAKE_BAD_TAG" ] && [ "$current" = "$NMTK_FAKE_BAD_TAG" ]; then
      exit 22
    fi
    printf '{"version":"1.0.0"}'
    ;;
esac
exit 0
"""


def _write_executable(directory: Path, name: str, body: str) -> None:
    path = directory / name
    path.write_text(body)
    path.chmod(0o755)


def _run_install(
    tmp_path: Path,
    *,
    bad_tag: str,
    extra_args: tuple[str, ...] = (),
    extra_env: dict[str, str] | None = None,
    seed_migration_marker: bool = True,
) -> tuple[subprocess.CompletedProcess[str], str, str, str, Path]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    state = tmp_path / "state"
    state.mkdir()
    workdir = tmp_path / "deploy"
    workdir.mkdir()
    shutil.copy(INSTALL_SCRIPT, workdir / "install.sh")
    shutil.copy(STACK_SCRIPT, workdir / "nmtk-stack.sh")
    # An already-migrated host: the legacy data-migration step is skipped, so
    # these tests isolate the update failure rather than the first-run path.
    if seed_migration_marker:
        marker = workdir / ".migration-staging" / "p0-owner-v1.complete"
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text("done\n")
    home = tmp_path / "home"
    home.mkdir()

    _write_executable(bin_dir, "docker", FAKE_ENGINE)
    _write_executable(bin_dir, "podman", FAKE_ENGINE)
    _write_executable(bin_dir, "curl", FAKE_CURL)
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
    env = {
        **os.environ,
        "PATH": f"{bin_dir}:/usr/bin:/bin",
        "HOME": str(home),
        "NMTK_FAKE_LOG": str(state / "commands.log"),
        "NMTK_FAKE_STATE": str(state),
        "NMTK_FAKE_SUITE_API": SUITE_API,
        "NMTK_FAKE_LAUNCHER": LAUNCHER,
        "NMTK_FAKE_GOOD_TAG": "v1.0.0",
        "NMTK_FAKE_GOOD_DIGEST": GOOD_DIGEST,
        "NMTK_FAKE_VERSION": "2.0.0",
        "NMTK_FAKE_BAD_TAG": bad_tag,
        "NMTK_DEPLOY_PULL_RETRY_DELAY": "0",
        "NMTK_DEPLOY_HEALTH_ATTEMPTS": "2",
        "NMTK_DEPLOY_HEALTH_INTERVAL": "0",
    }
    if extra_env:
        env.update(extra_env)

    result = subprocess.run(
        [
            "bash",
            "install.sh",
            "docker",
            "9000",
            "latest",
            "false",
            "127.0.0.1",
            str(status_file),
            str(log_file),
            *extra_args,
        ],
        cwd=workdir,
        capture_output=True,
        text=True,
        env=env,
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
        workdir,
    )


def test_failed_update_rolls_back_to_the_last_good_release(tmp_path: Path) -> None:
    result, status, log, commands, workdir = _run_install(tmp_path, bad_tag="2.0.0")

    assert result.returncode == 1, f"{status}\n{log}\n{result.stderr}"
    assert status.startswith("failed|100|"), status
    assert "rolled back to 1.0.0" in status, status
    assert "Rolling back to 1.0.0" in log, log
    # The exact pre-update image was restored by digest, then started from a
    # local-only tag so the rollback does not depend on the registry.
    assert f"pull {SUITE_API}@{GOOD_DIGEST}" in commands, commands
    assert "nmtk-lastgood" in commands, commands
    # The service is left on the restored release, not the broken one.
    assert (workdir / ".nmtk-state" / "pending-update.state").is_file()


def test_schema_migration_release_is_held_not_rolled_back(tmp_path: Path) -> None:
    result, status, log, commands, _ = _run_install(
        tmp_path,
        bad_tag="2.0.0",
        extra_args=("--schema-migration", "true"),
    )

    assert result.returncode == 1, f"{status}\n{log}\n{result.stderr}"
    assert status.startswith("failed|100|"), status
    assert "schema or data migration" in status, status
    assert "not rolled back automatically" in status, status
    assert "nmtk-lastgood" not in commands, commands


def test_hold_policy_does_not_roll_back(tmp_path: Path) -> None:
    result, status, log, commands, _ = _run_install(
        tmp_path,
        bad_tag="2.0.0",
        extra_args=("--rollback-policy", "hold"),
    )

    assert result.returncode == 1, f"{status}\n{log}\n{result.stderr}"
    assert status.startswith("failed|100|"), status
    assert "nmtk-lastgood" not in commands, commands


def test_unflagged_data_migration_detected_on_host_blocks_rollback(
    tmp_path: Path,
) -> None:
    result, status, log, commands, _ = _run_install(
        tmp_path, bad_tag="2.0.0", seed_migration_marker=False
    )

    assert result.returncode == 1, f"{status}\n{log}\n{result.stderr}"
    assert "schema or data migration" in status, status
    assert "nmtk-lastgood" not in commands, commands


def test_successful_update_pins_release_and_records_last_good(tmp_path: Path) -> None:
    result, status, log, commands, workdir = _run_install(tmp_path, bad_tag="")

    assert result.returncode == 0, f"{status}\n{log}\n{result.stderr}"
    assert status.startswith("completed|100|"), status
    assert "Pinned deploy to release 2.0.0" in log, log
    last_good = (workdir / ".nmtk-state" / "last-good.state").read_text()
    assert "version|2.0.0" in last_good, last_good
    assert not (workdir / ".nmtk-state" / "pending-update.state").exists()


@pytest.mark.parametrize("policy_env", ["auto"])
def test_rollback_policy_can_be_supplied_by_environment(
    tmp_path: Path, policy_env: str
) -> None:
    result, status, log, commands, _ = _run_install(
        tmp_path,
        bad_tag="2.0.0",
        extra_env={"NMTK_ROLLBACK_POLICY": policy_env},
    )

    assert result.returncode == 1, f"{status}\n{log}\n{result.stderr}"
    assert "rolled back to 1.0.0" in status, status
