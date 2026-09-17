"""App-credential login (launcher_auth.py) -- the connect-time counterpart
to the admin token, minted by install.sh --app-username/--app-password."""

from __future__ import annotations

import json
import os
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest import mock

import bcrypt
from base import LauncherControlServiceTestBase

import nmtk.launcher_control.server as launcher_server
from nmtk.launcher_control.launcher_auth import (
    CredentialStoreError,
    InvalidCredentialsError,
)


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

    def test_login_raises_when_users_file_missing(self) -> None:
        missing = str(self.repo_root / "no-such-users.json")
        with mock.patch.dict(
            os.environ, {"NMTK_APP_USERS_FILE": missing}, clear=False
        ):
            with self.assertRaises(CredentialStoreError):
                self.state.login({"username": "alice", "password": "secret"})

    def test_login_raises_when_users_file_is_invalid_json(self) -> None:
        broken = self.repo_root / "broken-users.json"
        broken.write_text("not-json", encoding="utf-8")
        with mock.patch.dict(
            os.environ, {"NMTK_APP_USERS_FILE": str(broken)}, clear=False
        ):
            with self.assertRaises(CredentialStoreError):
                self.state.login({"username": "alice", "password": "secret"})

    def test_login_logs_structured_error_when_users_file_missing(self) -> None:
        missing = str(self.repo_root / "no-such-users.json")
        with mock.patch.dict(
            os.environ, {"NMTK_APP_USERS_FILE": missing}, clear=False
        ):
            with self.assertLogs("nmtk.launcher_control.launcher_auth", level="ERROR") as logs:
                with self.assertRaises(CredentialStoreError):
                    self.state.login({"username": "alice", "password": "secret"})
        self.assertTrue(
            any("app_users_load_failed" in record.message for record in logs.records)
        )

    def test_login_http_returns_503_when_credential_store_broken(self) -> None:
        missing = str(self.repo_root / "no-such-users.json")
        server = launcher_server.create_server("127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 1.0)
        base = f"http://127.0.0.1:{server.server_address[1]}"
        request = urllib.request.Request(
            f"{base}/api/launcher/auth/login",
            data=json.dumps({"username": "alice", "password": "secret"}).encode(
                "utf-8"
            ),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with mock.patch.dict(
            os.environ, {"NMTK_APP_USERS_FILE": missing}, clear=False
        ):
            with self.assertRaises(urllib.error.HTTPError) as exc_info:
                urllib.request.urlopen(request, timeout=5)
        payload = json.loads(exc_info.exception.read().decode("utf-8"))
        self.assertEqual(exc_info.exception.code, 503)
        self.assertEqual(
            payload["detail"]["code"],
            "credential_store_unavailable",
        )
        self.assertIn("credential store", payload["detail"]["message"].lower())
        self.assertTrue(payload["detail"]["retryable"])

    def test_session_token_from_login_is_valid_until_expiry(self) -> None:
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

        self.assertTrue(self.state.is_session_token_valid(result["token"]))
        self.assertFalse(self.state.is_session_token_valid("not-a-real-token"))
        self.assertFalse(self.state.is_session_token_valid(""))

        # An expired session is rejected and pruned, not just rejected once.
        self.state._sessions[result["token"]]["expiresAt"] = 0
        self.assertFalse(self.state.is_session_token_valid(result["token"]))
        self.assertNotIn(result["token"], self.state._sessions)


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
