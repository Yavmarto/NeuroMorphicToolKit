"""App-credential login (launcher_auth.py) -- the connect-time counterpart
to the admin token, minted by install.sh --app-username/--app-password."""

from __future__ import annotations

import json
import os
import unittest
from pathlib import Path
from unittest import mock

import bcrypt
from base import LauncherControlServiceTestBase

from nmtk.launcher_control.launcher_auth import InvalidCredentialsError


class TestLauncherAppCredentialLogin(LauncherControlServiceTestBase):
    def _write_users_file(self, users: dict[str, str]) -> str:
        path = self.repo_root / "credentials-users.json"
        path.write_text(json.dumps(users), encoding="utf-8")
        return str(path)

    def test_login_succeeds_with_matching_password(self) -> None:
        password_hash = bcrypt.hashpw(b"correct horse", bcrypt.gensalt()).decode(
            "utf-8"
        )
        users_file = self._write_users_file({"alice": password_hash})
        with mock.patch.dict(
            os.environ, {"NMTK_APP_USERS_FILE": users_file}, clear=False
        ):
            result = self.state.login(
                {"username": "alice", "password": "correct horse"}
            )
        self.assertEqual(result["username"], "alice")
        self.assertTrue(result["token"])

    def test_login_rejects_wrong_password(self) -> None:
        password_hash = bcrypt.hashpw(b"correct horse", bcrypt.gensalt()).decode(
            "utf-8"
        )
        users_file = self._write_users_file({"alice": password_hash})
        with mock.patch.dict(
            os.environ, {"NMTK_APP_USERS_FILE": users_file}, clear=False
        ):
            with self.assertRaises(InvalidCredentialsError):
                self.state.login({"username": "alice", "password": "wrong"})

    def test_login_rejects_unknown_username(self) -> None:
        users_file = self._write_users_file({})
        with mock.patch.dict(
            os.environ, {"NMTK_APP_USERS_FILE": users_file}, clear=False
        ):
            with self.assertRaises(InvalidCredentialsError):
                self.state.login({"username": "nobody", "password": "whatever"})

    def test_login_requires_username_and_password(self) -> None:
        with self.assertRaises(ValueError):
            self.state.login({"username": "", "password": ""})


class TestInstallScriptForwardsProvisionEnv(unittest.TestCase):
    def test_compose_run_forwards_app_credential_env_vars(self) -> None:
        # docker compose run does not auto-forward host env vars into the
        # container -- exporting NMTK_PROVISION_APP_USERNAME/PASSWORD for the
        # host-side `compose run` process alone leaves the containerized
        # python snippet unable to see them (KeyError at provision time).
        # `-e VAR` on the compose invocation is what actually forwards them.
        repo_root = Path(__file__).resolve().parents[2]
        install_sh = (
            repo_root
            / "nmtk"
            / "neuro_toolkit"
            / "assets"
            / "deployment"
            / "install.sh"
        ).read_text(encoding="utf-8")
        provision_block = install_sh.split("Provisioning app credentials", 1)[1]
        compose_run_call = provision_block.split("write_status", 1)[0]
        self.assertIn("-e NMTK_PROVISION_APP_USERNAME", compose_run_call)
        self.assertIn("-e NMTK_PROVISION_APP_PASSWORD", compose_run_call)
        # launcher-control's cap_drop: ALL strips CAP_DAC_OVERRIDE, so --user
        # 0:0 alone can't write users.json (owned by the deployment account,
        # not root) -- needs this restored the same way --cap-add CHOWN
        # restores it for the workspace-storage step above.
        self.assertIn("--cap-add DAC_OVERRIDE", compose_run_call)
        # chmod needs CAP_FOWNER to re-mode a file it doesn't own, also
        # stripped by cap_drop: ALL, and it's redundant besides -- install.sh
        # already leaves the file at 0644 before this container ever runs, and
        # writing to an existing file never changes its mode bits. Confirmed
        # on the live dev host: the write itself succeeded, only the trailing
        # os.chmod() call failed with EPERM.
        self.assertNotIn("os.chmod", compose_run_call)

    def test_users_json_bind_mount_uses_its_own_source_directory(self) -> None:
        # Compose collapses two file bind mounts that share a source
        # directory into one directory-level bind, taking the strictest mode
        # of the two -- so admin-token's :ro would silently make users.json
        # read-only too if both lived directly under credentials/ (confirmed
        # on the live dev host: writes failed with EROFS despite --user 0:0
        # and --cap-add DAC_OVERRIDE). users.json must live in a subdirectory
        # admin-token doesn't share.
        repo_root = Path(__file__).resolve().parents[2]
        compose_yml = (repo_root / "docker-compose.remote.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("./credentials/app/users.json:/app/credentials/users.json", compose_yml)
        self.assertNotIn(
            "./credentials/users.json:/app/credentials/users.json", compose_yml
        )
