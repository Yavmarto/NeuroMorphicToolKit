"""Launcher control service tests: remote host setup (deploy directory resolution, container engine install)."""

from pathlib import Path
from unittest import mock

from base import LauncherControlServiceTestBase


class TestLauncherDeploymentSetup(LauncherControlServiceTestBase):
    def test_resolve_remote_deploy_dir_uses_configured_install_root(self) -> None:
        """An explicitly configured install_root is used as-is, not overridden."""

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="remote-configured",
            display_name="Remote Configured",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.3",
            auth_mode="none",
            install_root="/srv/nmtk",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        captured: list[list[str]] = []

        def fake_run(cmd: list[str], **kwargs: object) -> mock.Mock:
            captured.append(cmd)
            return mock.Mock(returncode=0, stdout="/srv/nmtk\n", stderr="")

        with mock.patch(
            "nmtk.launcher_control.deployment_executors.subprocess.run",
            side_effect=fake_run,
        ):
            resolved = executor._resolve_remote_deploy_dir(target)

        assert resolved == "/srv/nmtk"
        assert captured, "expected subprocess.run to be called"
        remote_cmd = captured[0][-1]
        assert "/srv/nmtk" in remote_cmd
        assert "mkdir -p" in remote_cmd and "pwd" in remote_cmd

    def test_resolve_remote_deploy_dir_defaults_to_home_directory(self) -> None:
        """With no install_root set, falls back to ~/nmtk-deploy, not a root-owned system path."""

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="remote-default",
            display_name="Remote Default",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.4",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        captured: list[list[str]] = []

        def fake_run(cmd: list[str], **kwargs: object) -> mock.Mock:
            captured.append(cmd)
            return mock.Mock(
                returncode=0, stdout="/home/deploy/nmtk-deploy\n", stderr=""
            )

        with mock.patch(
            "nmtk.launcher_control.deployment_executors.subprocess.run",
            side_effect=fake_run,
        ):
            resolved = executor._resolve_remote_deploy_dir(target)

        assert resolved == "/home/deploy/nmtk-deploy"
        remote_cmd = captured[0][-1]
        assert "~/nmtk-deploy" in remote_cmd
        assert "/opt/nmtk" not in remote_cmd

    def test_resolve_remote_deploy_dir_raises_friendly_error_on_permission_denied(
        self,
    ) -> None:
        """A permission-denied mkdir failure surfaces an actionable message, not raw stderr."""

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="remote-denied",
            display_name="Remote Denied",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.5",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        def fake_run(cmd: list[str], **kwargs: object) -> mock.Mock:
            return mock.Mock(
                returncode=1,
                stdout="",
                stderr="mkdir: cannot create directory 'nmtk-deploy': Permission denied",
            )

        with (
            mock.patch(
                "nmtk.launcher_control.deployment_executors.subprocess.run",
                side_effect=fake_run,
            ),
            self.assertRaises(RuntimeError) as excinfo,
        ):
            executor._resolve_remote_deploy_dir(target)

        message = str(excinfo.exception)
        assert "Permission denied" in message
        assert "home directory" in message

    def test_resolve_remote_deploy_dir_configured_permission_denied_mentions_install_root(
        self,
    ) -> None:
        """When a configured install_root is rejected, the error names it explicitly."""

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="remote-configured-denied",
            display_name="Remote Configured Denied",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.6",
            auth_mode="none",
            install_root="/opt/nmtk",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        def fake_run(cmd: list[str], **kwargs: object) -> mock.Mock:
            return mock.Mock(
                returncode=1,
                stdout="",
                stderr="mkdir: cannot create directory '/opt/nmtk': Permission denied",
            )

        with (
            mock.patch(
                "nmtk.launcher_control.deployment_executors.subprocess.run",
                side_effect=fake_run,
            ),
            self.assertRaises(RuntimeError) as excinfo,
        ):
            executor._resolve_remote_deploy_dir(target)

        message = str(excinfo.exception)
        assert "/opt/nmtk" in message
        assert "not writable" in message

    @staticmethod
    def _decode_engine_install_script(remote_cmd: str) -> str:
        """Decode the base64 payload from the generated remote command."""
        import base64

        echo_part = remote_cmd.split("echo ", 1)[1]
        encoded = echo_part.split(" | base64", 1)[0]
        return base64.b64decode(encoded).decode()

    def test_ensure_engine_installed_docker_checks_presence_before_sudo(self) -> None:
        """The `command -v docker` presence guard must run before the sudo
        gate, so an already-provisioned host never needs sudo access."""

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="engine-install-docker",
            display_name="Engine Install Docker",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.20",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        captured: list[str] = []

        def fake_ssh_run(tgt: object, remote_cmd: str, timeout: int = 600) -> None:
            captured.append(remote_cmd)

        with mock.patch.object(executor, "_ssh_run", side_effect=fake_ssh_run):
            executor._ensure_engine_installed(target)

        assert captured, "expected _ssh_run to be called"
        script = self._decode_engine_install_script(captured[0])
        presence_idx = script.index("command -v docker")
        sudo_idx = script.index("sudo_available")
        assert presence_idx < sudo_idx, script
        assert "exit 0" in script
        assert "get.docker.com" in script

    def test_ensure_engine_installed_podman_uses_apt(self) -> None:
        """Podman installs via apt + podman-compose, never the Docker install path."""

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="engine-install-podman",
            display_name="Engine Install Podman",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.21",
            auth_mode="none",
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        captured: list[str] = []

        def fake_ssh_run(tgt: object, remote_cmd: str, timeout: int = 600) -> None:
            captured.append(remote_cmd)

        with mock.patch.object(executor, "_ssh_run", side_effect=fake_ssh_run):
            executor._ensure_engine_installed(target)

        script = self._decode_engine_install_script(captured[0])
        assert "command -v podman" in script
        assert "apt-get install -y -qq podman podman-compose" in script
        assert "get.docker.com" not in script

    def test_ensure_engine_installed_password_auth_sets_sudo_password(self) -> None:
        """Password-auth targets reuse the SSH login password as the sudo
        password, mirroring `_ensure_docker_permissions`."""

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="engine-install-pw",
            display_name="Engine Install Pw",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.22",
            auth_mode="ssh_password",
            secret_refs={"sshPassword": "ref:my-secret"},
        )
        executor = DockerDeploymentExecutor(
            repo_root=Path("/tmp"), secret_resolver=lambda _ref: "supersecret"
        )
        captured: list[str] = []

        def fake_ssh_run(tgt: object, remote_cmd: str, timeout: int = 600) -> None:
            captured.append(remote_cmd)

        with mock.patch.object(executor, "_ssh_run", side_effect=fake_ssh_run):
            executor._ensure_engine_installed(target)

        assert captured[0].startswith(
            "env NMTK_DEPLOY_SUDO_PASSWORD=supersecret bash -c "
        )

    def test_ensure_engine_installed_key_auth_no_sudo_password_prefix(self) -> None:
        """Key-auth targets carry no password, so no sudo-password prefix is
        added -- elevation relies on passwordless sudo (or the host already
        having the engine installed, per the presence guard)."""

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="engine-install-key",
            display_name="Engine Install Key",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.23",
            auth_mode="ssh_key",
            secret_refs={"sshPrivateKey": "ref:my-key"},
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        captured: list[str] = []

        def fake_ssh_run(tgt: object, remote_cmd: str, timeout: int = 600) -> None:
            captured.append(remote_cmd)

        with mock.patch.object(executor, "_ssh_run", side_effect=fake_ssh_run):
            executor._ensure_engine_installed(target)

        assert "NMTK_DEPLOY_SUDO_PASSWORD" not in captured[0]
        assert captured[0].startswith("echo ")

    def test_deploy_remote_runs_engine_install_before_permissions_and_manifests(
        self,
    ) -> None:
        """`_ensure_engine_installed` must run before both the docker-only
        permission fix-up and copying manifests, for every remote deploy."""

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="engine-order",
            display_name="Engine Order",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.24",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        call_order: list[str] = []

        def emit(stage: str, message: str, percent: float) -> None:
            pass

        with (
            mock.patch.object(
                executor,
                "_resolve_remote_deploy_dir",
                return_value="/home/nmtk/nmtk-deploy",
            ),
            mock.patch.object(
                executor,
                "_ensure_engine_installed",
                side_effect=lambda t: call_order.append("install"),
            ),
            mock.patch.object(
                executor,
                "_ensure_docker_permissions",
                side_effect=lambda t: call_order.append("permissions"),
            ),
            mock.patch.object(
                executor,
                "_copy_manifests_to_remote",
                side_effect=lambda t, d: call_order.append("manifests"),
            ),
            mock.patch.object(
                executor,
                "_init_remote_secrets",
                side_effect=lambda t, d: call_order.append("secrets"),
            ),
            mock.patch.object(
                executor,
                "_ssh_run",
                side_effect=lambda *a, **k: call_order.append("ssh_run"),
            ),
            mock.patch.object(
                executor,
                "_health_check",
                side_effect=lambda t, host: call_order.append("health"),
            ),
            mock.patch.object(
                executor,
                "_jupyter_health_check",
                side_effect=lambda t: call_order.append("jupyter-health"),
            ),
        ):
            executor._deploy_remote(target, emit)

        assert call_order.index("install") < call_order.index("permissions"), call_order
        assert call_order.index("permissions") < call_order.index("manifests"), (
            call_order
        )

    def test_deploy_remote_aborts_before_manifests_when_engine_install_fails(
        self,
    ) -> None:
        """If install isn't possible (no sudo / no apt-get), the raised error
        must stop the deploy before any compose command runs."""

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="engine-install-fail",
            display_name="Engine Install Fail",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.25",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        def emit(stage: str, message: str, percent: float) -> None:
            pass

        with (
            mock.patch.object(
                executor,
                "_resolve_remote_deploy_dir",
                return_value="/home/nmtk/nmtk-deploy",
            ),
            mock.patch.object(
                executor,
                "_ensure_engine_installed",
                side_effect=RuntimeError(
                    "Remote command failed: apt-get not found; automatic Podman "
                    "install only supports Debian/Ubuntu"
                ),
            ),
            mock.patch.object(executor, "_copy_manifests_to_remote") as mock_copy,
            self.assertRaises(RuntimeError) as ctx,
        ):
            executor._deploy_remote(target, emit)

        assert "apt-get not found" in str(ctx.exception)
        mock_copy.assert_not_called()
