"""Launcher control service tests: Akida host SSH transport (base-url rewrites, docker gateway routing, credential modes)."""

from pathlib import Path
from unittest import mock

from base import LauncherControlServiceTestBase

import nmtk.launcher_control.server as launcher_server
from nmtk.launcher_control import (
    akida_host_service,
)


class TestLauncherAkidaHostSsh(LauncherControlServiceTestBase):
    def test_akida_request_base_url_rewrites_only_when_same_host_as_backend(
        self,
    ) -> None:
        """HTTP to the runtime uses the gateway alias, preserving scheme/port/path.

        Once provisioned the Neurochip runtime is a *host-level* systemd service,
        which this container can only reach through the alias — measured: the
        host's LAN address behaves like a closed port for host services.
        """
        self.assertEqual(
            akida_host_service._akida_request_base_url(
                "http://203.0.113.90:8002", {"sameHostAsBackend": True}
            ),
            "http://host.docker.internal:8002",
        )
        # Untouched when the host is a genuinely separate machine.
        self.assertEqual(
            akida_host_service._akida_request_base_url(
                "http://203.0.113.90:8002", {"sameHostAsBackend": False}
            ),
            "http://203.0.113.90:8002",
        )
        self.assertEqual(
            akida_host_service._akida_request_base_url("", {"sameHostAsBackend": True}),
            "",
        )
        # A URL without an explicit port keeps having none.
        self.assertEqual(
            akida_host_service._akida_request_base_url(
                "http://203.0.113.90", {"sameHostAsBackend": True}
            ),
            "http://host.docker.internal",
        )

    def test_akida_ssh_connect_host_uses_docker_gateway_when_same_host_as_backend(
        self,
    ) -> None:
        """`sameHostAsBackend` routes SSH through the container's gateway alias.

        From inside this container the host's own LAN address reaches no
        host-level service — see
        `nmtk/launcher_control/akida_host_service.py::_akida_ssh_connect_host`.
        """
        self.assertEqual(
            akida_host_service._akida_ssh_connect_host(
                {"host": "203.0.113.90", "sameHostAsBackend": True}
            ),
            "host.docker.internal",
        )
        self.assertEqual(
            akida_host_service._akida_ssh_connect_host(
                {"host": "203.0.113.90", "sameHostAsBackend": False}
            ),
            "203.0.113.90",
        )
        self.assertEqual(
            akida_host_service._akida_ssh_connect_host({"host": "203.0.113.90"}),
            "203.0.113.90",
        )

    def test_run_akida_ssh_targets_docker_gateway_when_same_host_as_backend(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Self-paired Akida",
                "host": "203.0.113.90",
                "username": "dev",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/fake-akida-key",
                "sameHostAsBackend": True,
            }
        )

        class _FakeStream:
            def readline(self) -> str:
                return ""

            def close(self) -> None:
                pass

        class _FakeProcess:
            stdout = _FakeStream()
            stderr = _FakeStream()
            returncode = 0

            def wait(self, timeout: float | None = None) -> int:
                del timeout
                return 0

            def kill(self) -> None:
                return None

        with mock.patch.object(
            akida_host_service.subprocess,
            "Popen",
            return_value=_FakeProcess(),
        ) as popen:
            self.state._run_akida_ssh(
                self.state._get_akida_host(host["id"]), "python3 --version"
            )

        command = popen.call_args.args[0]
        self.assertIn("dev@host.docker.internal", command)
        self.assertNotIn("dev@203.0.113.90", command)

    def test_akida_ssh_password_auth_requires_stored_password(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "198.51.100.60",
                "username": "operator",
                "authMode": "password",
            }
        )

        with self.assertRaisesRegex(
            RuntimeError,
            "No SSH password is configured for this Akida host",
        ):
            self.state._prepare_akida_ssh_invocation(
                self.state._get_akida_host(host["id"])
            )

    def test_akida_ssh_requires_supported_credential_mode(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "198.51.100.60",
                "username": "operator",
                "authMode": "none",
            }
        )

        with self.assertRaisesRegex(
            RuntimeError,
            "Akida host SSH operations require password or SSH-key authentication",
        ):
            self.state._prepare_akida_ssh_invocation(
                self.state._get_akida_host(host["id"])
            )

    def test_akida_ssh_password_auth_uses_askpass_without_sshpass(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "198.51.100.60",
                "username": "operator",
                "authMode": "password",
                "password": "secret",
            }
        )

        with mock.patch.object(launcher_server.shutil, "which", return_value=None):
            command, env, cleanup = self.state._prepare_akida_ssh_invocation(
                self.state._get_akida_host(host["id"])
            )

        self.assertNotIn("sshpass", command)
        self.assertIsNotNone(env)
        assert env is not None
        self.assertEqual(env["NMTK_AKIDA_PASSWORD"], "secret")
        self.assertIn("SSH_ASKPASS", env)
        askpass_path = Path(env["SSH_ASKPASS"])
        self.assertTrue(askpass_path.exists())
        self.assertIsNotNone(cleanup)
        assert cleanup is not None
        cleanup()
        self.assertFalse(askpass_path.exists())
