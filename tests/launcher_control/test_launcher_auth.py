"""App-credential login (launcher_auth.py) -- the connect-time counterpart
to the admin token, minted by install.sh --app-username/--app-password."""

from __future__ import annotations

import json
import os
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
