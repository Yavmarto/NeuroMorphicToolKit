"""Launcher control service tests: Akida host provisioning (preflight, service restart, install-status sentinel, token read-back)."""

import json
from unittest import mock

from base import LauncherControlServiceTestBase

import nmtk.launcher_control.server as launcher_server


class TestLauncherAkidaHostProvisioning(LauncherControlServiceTestBase):
    def test_apply_preflight_to_akida_host_marks_user_space_install_degraded(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
            }
        )

        updated = self.state._apply_preflight_to_akida_host(
            host["id"],
            {
                "preflight_status": launcher_server.PREFLIGHT_OK,
                "preflight_message": "Akida hardware runtime is ready.",
                "runtime_target": "hardware",
                "sdk_status": "deployable",
            },
            install_status={"installMode": "user-space"},
        )

        self.assertEqual(updated["state"], "degraded_optional_capability")
        self.assertIn(
            "Runtime is installed in user space.", updated["lastPreflightMessage"]
        )
        self.assertIn(
            "Enable passwordless sudo for 'operator'", updated["lastPreflightMessage"]
        )

    def test_restart_akida_host_services_returns_warning_for_user_space_install(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
            }
        )

        with mock.patch.object(
            self.state,
            "_read_remote_akida_install_status",
            return_value={"installMode": "user-space"},
        ):
            result = self.state.restart_akida_host_services(host["id"])

        self.assertEqual(result["host"]["state"], "degraded_optional_capability")
        self.assertIn("user space", result["warning"])
        self.assertIn("Enable passwordless sudo for 'operator'", result["warning"])
        self.assertIn("re-run Provision Runtime", result["warning"])

    def test_provision_akida_host_updates_paths_from_user_space_install_status(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/fake-akida-key",
            }
        )
        install_status = {
            "installMode": "user-space",
            "message": "Akida host installed in user space; auto-start requires privileged setup.",
            "runtimeApiUrl": "http://akida-box.local:8002",
            "controlApiUrl": "http://akida-box.local:8091",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "operator",
            "venvPath": "/home/operator/.local/share/neurochip-akida-host/venv",
            "installRoot": "/home/operator/.local/share/neurochip-akida-host",
            "tokenPath": "/home/operator/.local/share/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/home/operator/.local/share/neurochip-akida-host/install-status.json",
            "autoStartSupported": False,
        }
        install_output = (
            "[install-akida-host] done\n"
            f"INSTALL_STATUS_JSON={json.dumps(install_status, sort_keys=True)}\n"
        )

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ),
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(
                self.state, "_read_remote_akida_token", return_value="token-123"
            ),
            mock.patch.object(
                self.state,
                "fetch_akida_host_preflight",
                return_value={"host": {"state": "degraded_optional_capability"}},
            ),
        ):
            result = self.state.provision_akida_host(host["id"])

        updated = self.state.get_akida_host(host["id"])
        self.assertEqual(result["installStatus"]["installMode"], "user-space")
        self.assertEqual(
            updated["remoteInstallRoot"],
            "/home/operator/.local/share/neurochip-akida-host",
        )
        self.assertEqual(updated["serviceUser"], "operator")
        self.assertEqual(
            updated["tokenPath"],
            "/home/operator/.local/share/neurochip-akida-host/credentials/api-token",
        )
        self.assertEqual(
            updated["installStatusPath"],
            "/home/operator/.local/share/neurochip-akida-host/install-status.json",
        )
        self.assertEqual(updated["credentialRef"], "token-123")
        self.assertEqual(updated["runtimeApiUrl"], "http://akida-box.local:8002")
        self.assertEqual(updated["controlApiUrl"], "http://akida-box.local:8091")

    def test_provision_akida_host_falls_back_to_remote_status_when_sentinel_blank(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/fake-akida-key",
            }
        )
        install_status = {
            "installMode": "systemd",
            "message": "Akida host installation completed.",
            "runtimeApiUrl": "http://akida-box.local:8002",
            "controlApiUrl": "http://akida-box.local:8091",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "neurochip",
            "venvPath": "/opt/neurochip-akida-host/venv",
            "installRoot": "/opt/neurochip-akida-host",
            "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/opt/neurochip-akida-host/install-status.json",
            "autoStartSupported": True,
        }
        install_output = "[install-akida-host] done\nINSTALL_STATUS_JSON=\n"

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ),
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_akida_install_status",
                return_value=install_status,
            ) as read_status,
            mock.patch.object(
                self.state, "_read_remote_akida_token", return_value="token-123"
            ),
            mock.patch.object(
                self.state,
                "fetch_akida_host_preflight",
                return_value={"host": {"state": "ready"}},
            ),
        ):
            result = self.state.provision_akida_host(host["id"])

        self.assertEqual(result["installStatus"]["installMode"], "systemd")
        read_status.assert_called_once()

    def test_provision_akida_host_parses_multiline_install_status_sentinel(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/fake-akida-key",
            }
        )
        install_status = {
            "installMode": "systemd",
            "message": "Akida host installation completed.",
            "runtimeApiUrl": "http://akida-box.local:8002",
            "controlApiUrl": "http://akida-box.local:8091",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "neurochip",
            "venvPath": "/opt/neurochip-akida-host/venv",
            "installRoot": "/opt/neurochip-akida-host",
            "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/opt/neurochip-akida-host/install-status.json",
            "autoStartSupported": True,
            "state": "ready",
        }
        install_output = (
            "INSTALL_STATUS_JSON={\n"
            '  "autoStartSupported": true,\n'
            '  "controlApiUrl": "http://akida-box.local:8091",\n'
            '  "hostOs": "linux",\n'
            '  "installMode": "systemd",\n'
            '  "installRoot": "/opt/neurochip-akida-host",\n'
            '  "installStatusPath": "/opt/neurochip-akida-host/install-status.json",\n'
            '  "message": "Akida host installation completed.",\n'
            '  "pythonVersion": "3.11.8",\n'
            '  "runtimeApiUrl": "http://akida-box.local:8002",\n'
            '  "serviceUser": "neurochip",\n'
            '  "state": "ready",\n'
            '  "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",\n'
            '  "venvPath": "/opt/neurochip-akida-host/venv"\n'
            "}\n"
            "[install-akida-host] Install script completed successfully\n"
        )

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ),
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(
                self.state, "_read_remote_akida_token", return_value="token-123"
            ),
            mock.patch.object(
                self.state,
                "fetch_akida_host_preflight",
                return_value={"host": {"state": "ready"}},
            ),
        ):
            result = self.state.provision_akida_host(host["id"])

        self.assertEqual(result["installStatus"], install_status)
        updated = self.state.get_akida_host(host["id"])
        self.assertEqual(updated["runtimeApiUrl"], "http://akida-box.local:8002")
        self.assertEqual(updated["controlApiUrl"], "http://akida-box.local:8091")

    def test_provision_akida_host_passes_sudo_password_without_logging_it(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "password",
                "password": "secret",
            }
        )
        install_status = {
            "installMode": "systemd",
            "message": "Akida host installation completed.",
            "runtimeApiUrl": "http://akida-box.local:8002",
            "controlApiUrl": "http://akida-box.local:8091",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "neurochip",
            "venvPath": "/opt/neurochip-akida-host/venv",
            "installRoot": "/opt/neurochip-akida-host",
            "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/opt/neurochip-akida-host/install-status.json",
            "autoStartSupported": True,
        }
        install_output = (
            "[install-akida-host] done\n"
            f"INSTALL_STATUS_JSON={json.dumps(install_status, sort_keys=True)}\n"
        )

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ) as run_ssh,
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(
                self.state, "_read_remote_akida_token", return_value="token-123"
            ),
            mock.patch.object(
                self.state,
                "fetch_akida_host_preflight",
                return_value={"host": {"state": "ready"}},
            ),
        ):
            self.state.provision_akida_host(host["id"])

        install_call = run_ssh.call_args_list[1]
        remote_command = install_call.args[1]
        display_command = install_call.kwargs["display_command"]
        self.assertIn("NMTK_AKIDA_SUDO_PASSWORD=secret", remote_command)
        self.assertIn("NMTK_AKIDA_SUDO_PASSWORD=<redacted>", display_command)
        self.assertNotIn("secret", display_command)

    def test_read_remote_akida_token_uses_sudo_password_without_logging_it(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "password",
                "password": "secret",
            }
        )

        with mock.patch.object(
            self.state,
            "_run_akida_ssh",
            return_value="token-123\n",
        ) as run_ssh:
            token = self.state._read_remote_akida_token(
                self.state._get_akida_host(host["id"]),
                install_status={"installMode": "systemd"},
            )

        self.assertEqual(token, "token-123")
        remote_command = run_ssh.call_args.args[1]
        display_command = run_ssh.call_args.kwargs["display_command"]
        self.assertIn("printf '%s\\n' secret | sudo -S -p '' cat", remote_command)
        self.assertIn("sudo -S -p '' cat", remote_command)
        self.assertIn("printf '%s\\n' <redacted> | sudo -S -p '' cat", display_command)
        self.assertNotIn("NMTK_AKIDA_SUDO_PASSWORD", remote_command)
        self.assertNotIn("secret", display_command)

    def test_provision_akida_host_fails_when_remote_token_is_empty(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/fake-akida-key",
            }
        )
        install_status = {
            "installMode": "systemd",
            "message": "Akida host installation completed.",
            "runtimeApiUrl": "http://unresolvable-hostname:8002",
            "controlApiUrl": "http://unresolvable-hostname:8091",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "neurochip",
            "venvPath": "/opt/neurochip-akida-host/venv",
            "installRoot": "/opt/neurochip-akida-host",
            "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/opt/neurochip-akida-host/install-status.json",
            "autoStartSupported": True,
        }
        install_output = (
            "[install-akida-host] done\n"
            f"INSTALL_STATUS_JSON={json.dumps(install_status, sort_keys=True)}\n"
        )

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ),
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(self.state, "_read_remote_akida_token", return_value=""),
        ):
            result = self.state.provision_akida_host(host["id"])

        self.assertIn("empty value", result["error"])
