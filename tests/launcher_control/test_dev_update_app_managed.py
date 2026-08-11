"""Shell-backed regression coverage for app-owned developer updates."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts" / "dev" / "app_managed_update.sh"
CHANGED_PATHS = ROOT / "scripts" / "dev" / "changed_paths.sh"
DEV_UPDATE = ROOT / "scripts" / "dev_update.sh"


def _write_executable(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(0o755)


def _git(*args: str, cwd: Path) -> None:
    subprocess.run(
        ["git", *args],
        cwd=cwd,
        check=True,
        text=True,
        capture_output=True,
        env={
            **os.environ,
            "GIT_AUTHOR_NAME": "NMTK test",
            "GIT_AUTHOR_EMAIL": "test@example.invalid",
            "GIT_COMMITTER_NAME": "NMTK test",
            "GIT_COMMITTER_EMAIL": "test@example.invalid",
        },
    )


def _resolve_built_image(
    tmp_path: Path,
    compose_config: dict[str, object],
    *,
    image_id: str = "sha256:built-image",
) -> subprocess.CompletedProcess[str]:
    call_log = tmp_path / "image-lookup.log"
    return subprocess.run(
        [
            "bash",
            "-c",
            """
dev_update=$1
service=$2
set --
source "$dev_update"
compose_probe() { printf '%s' "$NMTK_TEST_COMPOSE_CONFIG"; }
remote_probe() {
  printf '%s\n' "$*" >> "$NMTK_TEST_CALL_LOG"
  [ -z "$NMTK_TEST_IMAGE_ID" ] || printf '%s\n' "$NMTK_TEST_IMAGE_ID"
}
resolve_built_image_id "$service"
""",
            "_",
            str(DEV_UPDATE),
            "launcher-control",
        ],
        cwd=ROOT,
        env={
            **os.environ,
            "NMTK_TEST_COMPOSE_CONFIG": json.dumps(compose_config),
            "NMTK_TEST_IMAGE_ID": image_id,
            "NMTK_TEST_CALL_LOG": str(call_log),
        },
        text=True,
        capture_output=True,
        check=False,
    )


def test_app_managed_update_helper_is_executable() -> None:
    assert os.access(HELPER, os.X_OK)


def test_built_image_lookup_does_not_require_a_compose_container(
    tmp_path: Path,
) -> None:
    result = _resolve_built_image(
        tmp_path,
        {
            "name": "nmtk-deploy",
            "services": {"launcher-control": {"build": {}}},
        },
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "sha256:built-image"
    calls = (tmp_path / "image-lookup.log").read_text(encoding="utf-8")
    assert "image inspect nmtk-deploy-launcher-control" in calls
    assert "compose images" not in calls


def test_built_image_lookup_honors_an_explicit_image_name(
    tmp_path: Path,
) -> None:
    result = _resolve_built_image(
        tmp_path,
        {
            "name": "nmtk-deploy",
            "services": {
                "launcher-control": {
                    "build": {},
                    "image": "ghcr.io/example/launcher-control:dev",
                }
            },
        },
    )

    assert result.returncode == 0, result.stderr
    calls = (tmp_path / "image-lookup.log").read_text(encoding="utf-8")
    assert "image inspect ghcr.io/example/launcher-control:dev" in calls


def test_built_image_lookup_fails_actionably_when_image_is_missing(
    tmp_path: Path,
) -> None:
    result = _resolve_built_image(
        tmp_path,
        {
            "name": "nmtk-deploy",
            "services": {"launcher-control": {"build": {}}},
        },
        image_id="",
    )

    assert result.returncode != 0
    assert (
        "built launcher-control image nmtk-deploy-launcher-control is missing"
        in result.stderr
    )


def test_changed_paths_expands_dirty_submodule_files(tmp_path: Path) -> None:
    child = tmp_path / "child-source"
    child.mkdir()
    _git("init", cwd=child)
    (child / "backend.py").write_text("OLD = True\n", encoding="utf-8")
    _git("add", "backend.py", cwd=child)
    _git("commit", "-m", "initial", cwd=child)

    parent = tmp_path / "parent"
    parent.mkdir()
    _git("init", cwd=parent)
    _git(
        "-c",
        "protocol.file.allow=always",
        "submodule",
        "add",
        str(child),
        "Neurochip",
        cwd=parent,
    )
    _git("commit", "-am", "initial", cwd=parent)
    (parent / "Neurochip" / "backend.py").write_text(
        "OLD = False\n", encoding="utf-8"
    )

    result = subprocess.run(
        [
            "bash",
            "-c",
            'source "$1"; nmtk_local_uncommitted_paths "$2"',
            "_",
            str(CHANGED_PATHS),
            str(parent),
        ],
        check=True,
        text=True,
        capture_output=True,
    )

    assert "Neurochip/backend.py" in result.stdout.splitlines()


def test_dev_update_ignores_generated_backend_logs() -> None:
    result = subprocess.run(
        [
            "bash",
            str(DEV_UPDATE),
            "--explain",
            "neurocnl/backend/logs/neurocnl.log",
        ],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )

    assert "nothing — not a backend runtime path" in result.stdout


def test_app_managed_handoff_reloads_and_recreates_only_selected_service(
    tmp_path: Path,
) -> None:
    deploy_dir = tmp_path / "deploy"
    deploy_dir.mkdir()
    for name in (
        "docker-compose.yml",
        "docker-compose.prod.yml",
        "docker-compose.remote.yml",
    ):
        (deploy_dir / name).write_text("services: {}\n", encoding="utf-8")

    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    call_log = tmp_path / "calls.log"
    _write_executable(
        fake_bin / "podman",
        """#!/usr/bin/env bash
set -eu
if [ "${NMTK_TEST_REQUIRE_SAFE_CWD:-0}" = "1" ] && \
   [ "$1" != "compose" ] && [ "$PWD" != "/" ]; then
  printf 'cannot chdir to %s: Permission denied\n' "$PWD" >&2
  exit 73
fi
printf '%s\\n' "$*" >> "$NMTK_TEST_CALL_LOG"
case "$1" in
  ps) printf '%s\\n' existing-launcher ;;
  inspect)
    case "$*" in
      *ImageName*) printf '%s\\n' ghcr.io/example/launcher-control:0.6.0 ;;
      *Health*) printf '%s\\n' unhealthy ;;
      *State.Status*) printf '%s\\n' running ;;
      *) printf '%s\\n' sha256:previous-image ;;
    esac
    ;;
  exec) exit 0 ;;
esac
""",
    )
    archive_dir = Path("/tmp") / f"nmtk-dev-update.pytest-{os.getpid()}"
    archive_dir.mkdir(exist_ok=True)
    archive = archive_dir / "launcher-control.tar"
    archive.write_bytes(b"image")

    env = {
        **os.environ,
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "NMTK_APP_UPDATE_TESTING": "1",
        "NMTK_APP_DEPLOY_HOME": str(tmp_path),
        "NMTK_APP_DEPLOY_UID": str(os.getuid()),
        "NMTK_APP_DEPLOY_DIR": str(deploy_dir),
        "NMTK_TEST_CALL_LOG": str(call_log),
        "NMTK_TEST_REQUIRE_SAFE_CWD": "1",
    }
    result = subprocess.run(
        [
            "bash",
            str(HELPER),
            "launcher-control",
            str(archive),
            "localhost/nmtk-dev-launcher-control:test",
        ],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    calls = call_log.read_text(encoding="utf-8")
    assert f"load -i {archive}" in calls
    assert (
        "tag localhost/nmtk-dev-launcher-control:test "
        "ghcr.io/example/launcher-control:0.6.0"
    ) in calls
    assert "up -d --no-deps --force-recreate launcher-control" in calls
    assert "exec existing-launcher python -c" in calls
    assert "http://127.0.0.1:8091/health" in calls
    assert not archive.exists()


def test_app_managed_helper_installs_a_scoped_passwordless_entry(
    tmp_path: Path,
) -> None:
    deploy_dir = tmp_path / "deploy"
    deploy_dir.mkdir()
    for name in (
        "docker-compose.yml",
        "docker-compose.prod.yml",
        "docker-compose.remote.yml",
    ):
        (deploy_dir / name).write_text("services: {}\n", encoding="utf-8")

    installed_helper = tmp_path / "libexec" / "nmtk-app-managed-update"
    sudoers_file = tmp_path / "sudoers.d" / "nmtk-dev-update"
    result = subprocess.run(
        ["bash", str(HELPER), "--install-for", "moosebun2"],
        cwd=ROOT,
        env={
            **os.environ,
            "NMTK_APP_UPDATE_TESTING": "1",
            "NMTK_APP_DEPLOY_HOME": str(tmp_path),
            "NMTK_APP_DEPLOY_UID": str(os.getuid()),
            "NMTK_APP_DEPLOY_DIR": str(deploy_dir),
            "NMTK_APP_UPDATE_INSTALLED_HELPER": str(installed_helper),
            "NMTK_APP_UPDATE_SUDOERS_FILE": str(sudoers_file),
        },
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert installed_helper.read_bytes() == HELPER.read_bytes()
    assert installed_helper.stat().st_mode & 0o777 == 0o755
    assert sudoers_file.read_text(encoding="utf-8") == (
        "moosebun2 ALL=(root) NOPASSWD: "
        f"{installed_helper} *\n"
    )
    assert sudoers_file.stat().st_mode & 0o777 == 0o440


def test_dev_update_reuses_the_installed_helper_without_scp_or_password(
    tmp_path: Path,
) -> None:
    call_log = tmp_path / "calls.log"
    result = subprocess.run(
        [
            "bash",
            "-c",
            r'''
dev_update="$1"
set --
source "$dev_update"
remote() {
  printf 'remote %s\n' "$*" >> "$NMTK_TEST_CALL_LOG"
  case "$*" in
    "mktemp -d /tmp/nmtk-dev-update.XXXXXX")
      printf '/tmp/nmtk-dev-update.test\n'
      ;;
  esac
}
remote_probe() {
  printf 'probe %s\n' "$*" >> "$NMTK_TEST_CALL_LOG"
  case "$*" in
    *"nmtk-app-managed-update' --version"*)
      printf 'nmtk-app-managed-update 2\n'
      ;;
  esac
}
compose_remote() {
  printf 'compose %s\n' "$*" >> "$NMTK_TEST_CALL_LOG"
}
resolve_built_image_id() {
  printf 'sha256:built-image\n'
}
scp() {
  printf 'scp %s\n' "$*" >> "$NMTK_TEST_CALL_LOG"
  return 97
}
app_managed_update_services launcher-control
''',
            "_",
            str(DEV_UPDATE),
        ],
        cwd=ROOT,
        env={**os.environ, "NMTK_TEST_CALL_LOG": str(call_log)},
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    calls = call_log.read_text(encoding="utf-8")
    assert "scp " not in calls
    assert (
        "sudo -n -- /usr/local/libexec/nmtk-app-managed-update "
        "launcher-control /tmp/nmtk-dev-update.test/launcher-control.tar"
    ) in calls


def test_app_managed_handoff_restores_previous_image_after_failed_recreate(
    tmp_path: Path,
) -> None:
    deploy_dir = tmp_path / "deploy"
    deploy_dir.mkdir()
    for name in (
        "docker-compose.yml",
        "docker-compose.prod.yml",
        "docker-compose.remote.yml",
    ):
        (deploy_dir / name).write_text("services: {}\n", encoding="utf-8")

    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    call_log = tmp_path / "calls.log"
    recreate_count = tmp_path / "recreate-count"
    _write_executable(
        fake_bin / "podman",
        """#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$NMTK_TEST_CALL_LOG"
case "$1" in
  ps) printf '%s\\n' existing-launcher ;;
  inspect)
    case "$*" in
      *ImageName*) printf '%s\\n' ghcr.io/example/launcher-control:0.6.0 ;;
      *Health*) printf '%s\\n' healthy ;;
      *State.Status*) printf '%s\\n' running ;;
      *) printf '%s\\n' sha256:previous-image ;;
    esac
    ;;
  compose)
    case "$*" in
      *" up -d --no-deps --force-recreate launcher-control")
        if [ ! -f "$NMTK_TEST_RECREATE_COUNT" ]; then
          : > "$NMTK_TEST_RECREATE_COUNT"
          exit 1
        fi
        ;;
    esac
    ;;
  exec) exit 0 ;;
esac
""",
    )
    archive_dir = Path("/tmp") / f"nmtk-dev-update.rollback-{os.getpid()}"
    archive_dir.mkdir(exist_ok=True)
    archive = archive_dir / "launcher-control.tar"
    archive.write_bytes(b"image")

    result = subprocess.run(
        [
            "bash",
            str(HELPER),
            "launcher-control",
            str(archive),
            "localhost/nmtk-dev-launcher-control:test",
        ],
        cwd=ROOT,
        env={
            **os.environ,
            "PATH": f"{fake_bin}:{os.environ['PATH']}",
            "NMTK_APP_UPDATE_TESTING": "1",
            "NMTK_APP_DEPLOY_HOME": str(tmp_path),
            "NMTK_APP_DEPLOY_UID": str(os.getuid()),
            "NMTK_APP_DEPLOY_DIR": str(deploy_dir),
            "NMTK_TEST_CALL_LOG": str(call_log),
            "NMTK_TEST_RECREATE_COUNT": str(recreate_count),
        },
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode != 0
    assert "previous image was restored" in result.stderr
    calls = call_log.read_text(encoding="utf-8")
    assert (
        "tag sha256:previous-image ghcr.io/example/launcher-control:0.6.0"
        in calls
    )
    assert calls.count(
        "up -d --no-deps --force-recreate launcher-control"
    ) == 2
    assert not archive.exists()


@pytest.mark.parametrize(
    "service,archive",
    [
        ("launcher-control;bad", "/tmp/nmtk-dev-update.test/image.tar"),
        ("launcher-control", "/tmp/outside-image.tar"),
    ],
)
def test_app_managed_handoff_rejects_untrusted_arguments(
    tmp_path: Path, service: str, archive: str
) -> None:
    deploy_dir = tmp_path / "deploy"
    deploy_dir.mkdir()
    for name in (
        "docker-compose.yml",
        "docker-compose.prod.yml",
        "docker-compose.remote.yml",
    ):
        (deploy_dir / name).write_text("services: {}\n", encoding="utf-8")

    result = subprocess.run(
        ["bash", str(HELPER), service, archive, "source:test"],
        cwd=ROOT,
        env={
            **os.environ,
            "NMTK_APP_UPDATE_TESTING": "1",
            "NMTK_APP_DEPLOY_HOME": str(tmp_path),
            "NMTK_APP_DEPLOY_UID": str(os.getuid()),
            "NMTK_APP_DEPLOY_DIR": str(deploy_dir),
        },
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode != 0
