"""Launcher control service tests: one-time root SSH bootstrap."""

import os
import subprocess
from unittest import mock

from base import LauncherControlServiceTestBase

# Captured before any test applies mock.patch("...subprocess.run", ...) --
# `deployment_user_bootstrap.subprocess` is the same module object as this
# top-level `subprocess` import, so patching one patches both; tests that
# need to let ssh-keygen actually run must call through this reference, not
# re-import subprocess (which would just return the already-patched module).
_REAL_SUBPROCESS_RUN = subprocess.run


class TestDeploymentUserBootstrap(LauncherControlServiceTestBase):
    """One-time root SSH bootstrap: nmtk/launcher_control/deployment_user_bootstrap.py.

    Real `ssh-keygen` is allowed to run (fast, local, no network) so these
    tests exercise the real key-generation path; only the SSH call itself is
    faked, since that's the one that would otherwise need a real remote host.
    """

    def _fake_ssh_success(self, captured: list[list[str]]):

        def fake_run(cmd: list[str], **kwargs: object):
            if cmd[0] == "ssh-keygen":
                return _REAL_SUBPROCESS_RUN(cmd, **kwargs)
            captured.append(cmd)
            return mock.Mock(
                returncode=0,
                stdout="[nmtk-bootstrap] creating user 'nmtk'\n[nmtk-bootstrap] done\n",
                stderr="",
            )

        return fake_run

    @staticmethod
    def _decode_remote_script(remote_cmd: str) -> str:
        """Decode the base64 payload from the generated remote command."""
        import base64

        echo_part = remote_cmd.split("echo ", 1)[1]
        encoded = echo_part.split(" | base64", 1)[0]
        return base64.b64decode(encoded).decode()

    def test_ssh_root_bootstrap_script_contains_expected_steps(self) -> None:
        """The remote command must create the user, add it to docker, and install the key
        via sudo (not assuming the SSH login itself is literally root)."""

        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        captured: list[list[str]] = []
        with (
            mock.patch(
                "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
                side_effect=self._fake_ssh_success(captured),
            ),
            mock.patch(
                "nmtk.launcher_control.deployment_executors.shutil.which",
                return_value="/usr/bin/sshpass",
            ),
        ):
            result = ssh_root_bootstrap(
                host="10.0.0.9",
                root_username="root",
                root_password="totally-secret-root-pw",
            )

        assert result["username"] == "nmtk"
        assert "BEGIN OPENSSH PRIVATE KEY" in result["sshPrivateKey"]
        assert captured, "expected an ssh subprocess call"

        remote_cmd = captured[0][-1]
        script = self._decode_remote_script(remote_cmd)
        assert "sudo_cmd useradd --create-home --shell /bin/bash" in script
        assert "sudo_cmd usermod -aG docker" in script
        assert "authorized_keys" in script
        assert "sudo_cmd install -m 600" in script
        assert "sudo_available" in script

    def test_ssh_root_bootstrap_login_password_via_sshpass_not_argv(self) -> None:
        """The SSH *login* password must still travel via SSHPASS env var, never as an
        ssh argv item -- only the (separate, already-accepted) sudo-password prefix on
        the remote command is expected to carry it, covered by the next test."""

        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        captured: list[dict] = []

        def fake_run(cmd, **kwargs):
            if cmd[0] == "ssh-keygen":
                return _REAL_SUBPROCESS_RUN(cmd, **kwargs)
            captured.append({"cmd": cmd, "env": kwargs.get("env", {})})
            return mock.Mock(returncode=0, stdout="[nmtk-bootstrap] done\n", stderr="")

        with (
            mock.patch(
                "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
                side_effect=fake_run,
            ),
            mock.patch(
                "nmtk.launcher_control.deployment_executors.shutil.which",
                return_value="/usr/bin/sshpass",
            ),
        ):
            ssh_root_bootstrap(
                host="10.0.0.9",
                root_username="root",
                root_password="totally-secret-root-pw",
            )

        assert captured, "expected an ssh subprocess call"
        cmd = captured[0]["cmd"]
        # The password must not appear as its own ssh/sshpass argv token (e.g. a `-p`
        # style argument); it's only allowed to appear inside the trailing remote
        # command string, where it's the deliberate sudo-password prefix.
        assert "totally-secret-root-pw" not in cmd[:-1]
        assert captured[0]["env"].get("SSHPASS") == "totally-secret-root-pw"

    def test_ssh_root_bootstrap_sudo_password_reaches_decoder_environment(
        self,
    ) -> None:
        """The sudo password must be attached to the decoder Bash process."""

        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        captured: list[list[str]] = []
        with (
            mock.patch(
                "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
                side_effect=self._fake_ssh_success(captured),
            ),
            mock.patch(
                "nmtk.launcher_control.deployment_executors.shutil.which",
                return_value="/usr/bin/sshpass",
            ),
        ):
            ssh_root_bootstrap(
                host="10.0.0.9",
                root_username="root",
                root_password="totally-secret-root-pw",
            )

        remote_cmd = captured[0][-1]
        assert remote_cmd.startswith(
            "env NMTK_DEPLOY_SUDO_PASSWORD=totally-secret-root-pw bash -c "
        )

    def test_encode_remote_script_passes_environment_to_decoded_bash(self) -> None:
        from nmtk.launcher_control.deployment_contracts import encode_remote_script

        remote_cmd = encode_remote_script(
            'printf "%s" "$NMTK_DEPLOY_SUDO_PASSWORD"',
            env={"NMTK_DEPLOY_SUDO_PASSWORD": "correct horse battery staple"},
        )
        result = _REAL_SUBPROCESS_RUN(
            ["bash", "-c", remote_cmd],
            capture_output=True,
            text=True,
            check=False,
        )

        assert result.returncode == 0, result.stderr
        assert result.stdout == "correct horse battery staple"

    def test_ssh_root_bootstrap_no_sudo_password_prefix_for_key_auth(self) -> None:
        """SSH-key auth carries no password at all, so no sudo-password prefix is added --
        elevation for a key-authenticated non-root account relies on passwordless sudo."""

        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        captured: list[list[str]] = []
        with mock.patch(
            "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
            side_effect=self._fake_ssh_success(captured),
        ):
            ssh_root_bootstrap(
                host="10.0.0.9",
                root_username="root",
                root_private_key="-----BEGIN FAKE KEY-----\nabc\n-----END FAKE KEY-----\n",
            )

        remote_cmd = captured[0][-1]
        assert "NMTK_DEPLOY_SUDO_PASSWORD" not in remote_cmd
        assert remote_cmd.startswith("echo ")

    def test_ssh_root_bootstrap_sudo_unavailable_surfaces_actionable_error(
        self,
    ) -> None:
        """If sudo elevation isn't possible at all, the script's own check fails fast with
        a clear, actionable message rather than a cryptic permission-denied string."""

        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        def fake_run(cmd, **kwargs):
            if cmd[0] == "ssh-keygen":
                return _REAL_SUBPROCESS_RUN(cmd, **kwargs)
            return mock.Mock(
                returncode=1,
                stdout="[nmtk-bootstrap] ERROR: this account cannot run privileged commands"
                " (no root session, no passwordless/NOPASSWD sudo, and no sudo password"
                " available). Use a password-based login for an admin account, true root"
                " credentials, or configure NOPASSWD sudo for this account.\n",
                stderr="",
            )

        with (
            mock.patch(
                "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
                side_effect=fake_run,
            ),
            mock.patch(
                "nmtk.launcher_control.deployment_executors.shutil.which",
                return_value="/usr/bin/sshpass",
            ),
            self.assertRaises(RuntimeError) as excinfo,
        ):
            ssh_root_bootstrap(
                host="10.0.0.9",
                root_username="mooseryzen",
                root_password="not-actually-sudo-capable",
            )

        message = str(excinfo.exception)
        assert "cannot run privileged commands" in message
        assert "not-actually-sudo-capable" not in message

    def test_ssh_root_bootstrap_key_file_cleaned_up(self) -> None:
        """The root private key temp file must be 0600 during use and removed after."""
        import stat
        from unittest import mock

        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        observed_key_paths: list[str] = []

        def fake_run(cmd, **kwargs):
            if cmd[0] == "ssh-keygen":
                return _REAL_SUBPROCESS_RUN(cmd, **kwargs)
            if "-i" in cmd:
                key_path = cmd[cmd.index("-i") + 1]
                observed_key_paths.append(key_path)
                mode = stat.S_IMODE(os.stat(key_path).st_mode)
                assert mode == 0o600, f"expected key file mode 0600, got {oct(mode)}"
            return mock.Mock(returncode=0, stdout="[nmtk-bootstrap] done\n", stderr="")

        with mock.patch(
            "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
            side_effect=fake_run,
        ):
            ssh_root_bootstrap(
                host="10.0.0.9",
                root_username="root",
                root_private_key="-----BEGIN FAKE KEY-----\nabc\n-----END FAKE KEY-----\n",
            )

        assert observed_key_paths, "expected the root key to be written to a temp file"
        assert not os.path.exists(observed_key_paths[0]), (
            "root key temp file must be deleted after use"
        )

    def test_ssh_root_bootstrap_requires_exactly_one_credential(self) -> None:
        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        with self.assertRaises(ValueError):
            ssh_root_bootstrap(host="10.0.0.9", root_username="root")

        with self.assertRaises(ValueError):
            ssh_root_bootstrap(
                host="10.0.0.9",
                root_username="root",
                root_password="a",
                root_private_key="b",
            )

    def test_ssh_root_bootstrap_failure_does_not_leak_password(self) -> None:

        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        def fake_run(cmd, **kwargs):
            if cmd[0] == "ssh-keygen":
                return _REAL_SUBPROCESS_RUN(cmd, **kwargs)
            return mock.Mock(
                returncode=1,
                stdout="",
                stderr="Permission denied (publickey,password).",
            )

        with (
            mock.patch(
                "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
                side_effect=fake_run,
            ),
            mock.patch(
                "nmtk.launcher_control.deployment_executors.shutil.which",
                return_value="/usr/bin/sshpass",
            ),
            self.assertRaises(RuntimeError) as excinfo,
        ):
            ssh_root_bootstrap(
                host="10.0.0.9",
                root_username="root",
                root_password="totally-secret-root-pw",
            )

        message = str(excinfo.exception)
        assert "Permission denied" in message
        assert "totally-secret-root-pw" not in message

    def test_ssh_root_bootstrap_never_touches_secret_store(self) -> None:
        """The bootstrap path must never write through FileBackedSecretStore/DeploymentStore."""

        from nmtk.launcher_control.deployment_store import FileBackedSecretStore
        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        captured: list[list[str]] = []
        with (
            mock.patch(
                "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
                side_effect=self._fake_ssh_success(captured),
            ),
            mock.patch(
                "nmtk.launcher_control.deployment_executors.shutil.which",
                return_value="/usr/bin/sshpass",
            ),
            mock.patch.object(
                FileBackedSecretStore,
                "put",
                side_effect=AssertionError("must not persist root creds"),
            ),
        ):
            result = ssh_root_bootstrap(
                host="10.0.0.9",
                root_username="root",
                root_password="totally-secret-root-pw",
            )

        assert result["username"] == "nmtk"
