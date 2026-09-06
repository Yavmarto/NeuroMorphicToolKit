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
