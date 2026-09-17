"""Launcher control service tests: remote deploy execution (podman runtime, deploy flow, manifest copy)."""

from pathlib import Path
from unittest import mock

from base import LauncherControlServiceTestBase


class TestLauncherDeploymentDeploy(LauncherControlServiceTestBase):
    def test_remote_compose_cmd_podman_skips_docker_group_dance(self) -> None:
        """Podman is rootless by design: no `sg docker`/group-membership wrapper."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="compose-cmd-podman",
            display_name="Compose Cmd Podman",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
            container_engine="podman",
        )
        cmd = executor._remote_compose_cmd("/home/nmtk/nmtk-deploy", target, "pull")

        assert cmd.startswith("cd "), cmd
        assert (
            "podman compose --project-name nmtk -f docker-compose.yml "
            "-f docker-compose.prod.yml "
            "-f docker-compose.remote.yml pull" in cmd
        ), cmd
        assert "DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock" in cmd, cmd
        assert "sg docker" not in cmd, cmd
        assert "getent group docker" not in cmd, cmd

    def test_prepare_podman_runtime_configures_rootless_socket(self) -> None:

        from nmtk.launcher_control.deployment_contracts import (
            DeploymentTarget,
            podman_runtime_setup_script,
        )
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="podman-runtime",
            display_name="Podman Runtime",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
            auth_mode="ssh_password",
            secret_refs={"sshPassword": "ref:my-secret"},
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(
            repo_root=Path("/tmp"),
            secret_resolver=lambda _ref: "supersecret",
        )
        captured: list[str] = []

        with mock.patch.object(
            executor,
            "_ssh_run",
            side_effect=lambda _target, command, timeout=600: captured.append(command),
        ):
            executor._prepare_podman_runtime(target)

        assert len(captured) == 1
        assert captured[0].startswith(
            "env NMTK_DEPLOY_SUDO_PASSWORD=supersecret bash -c "
        )
        setup_script = podman_runtime_setup_script()
        assert "systemctl --user enable --now podman.socket" in setup_script
        assert "XDG_RUNTIME_DIR" in setup_script
        assert "DOCKER_HOST" in setup_script
        assert "Podman socket was not created" in setup_script

    def test_deploy_remote_prepares_podman_before_manifests(self) -> None:

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="podman-order",
            display_name="Podman Order",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        calls: list[str] = []

        def emit(_stage: str, _message: str, _percent: float) -> None:
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
                side_effect=lambda _target: calls.append("install"),
            ),
            mock.patch.object(
                executor,
                "_prepare_podman_runtime",
                side_effect=lambda _target: calls.append("podman-runtime"),
            ),
            mock.patch.object(
                executor,
                "_copy_manifests_to_remote",
                side_effect=lambda _target, _directory: calls.append("manifests"),
            ),
            mock.patch.object(
                executor,
                "_init_remote_secrets",
                side_effect=lambda _target, _directory: calls.append("secrets"),
            ),
            mock.patch.object(
                executor,
                "_ssh_run",
                side_effect=lambda *_args, **_kwargs: calls.append("compose"),
            ),
            mock.patch.object(
                executor,
                "_health_check",
                side_effect=lambda _target, host: calls.append("health"),
            ),
            mock.patch.object(
                executor,
                "_jupyter_health_check",
                side_effect=lambda _target: calls.append("jupyter-health"),
            ),
        ):
            executor._deploy_remote(target, emit)

        assert calls.index("install") < calls.index("podman-runtime"), calls
        assert calls.index("podman-runtime") < calls.index("manifests"), calls
        assert calls.count("compose") == 8, calls

    def test_remote_deploy_cleans_project_before_pull_and_up(self) -> None:

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="cleanup-order",
            display_name="Cleanup Order",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        commands: list[str] = []

        with (
            mock.patch.object(
                executor,
                "_resolve_remote_deploy_dir",
                return_value="/home/nmtk/nmtk-deploy",
            ),
            mock.patch.object(executor, "_ensure_engine_installed"),
            mock.patch.object(executor, "_prepare_podman_runtime"),
            mock.patch.object(executor, "_copy_manifests_to_remote"),
            mock.patch.object(executor, "_init_remote_secrets"),
            mock.patch.object(
                executor,
                "_ssh_run",
                side_effect=lambda _target, command, timeout=600: commands.append(
                    command
                ),
            ),
            mock.patch.object(executor, "_health_check"),
            mock.patch.object(executor, "_jupyter_health_check"),
        ):
            executor._deploy_remote(target, lambda *_args: None)

        assert len(commands) == 8, commands
        assert "--project-name nmtk" in commands[1], commands
        assert all("--project-name nmtk" in command for command in commands[4:7]), (
            commands
        )
        assert "down --remove-orphans" in commands[4], commands
        assert " pull" in commands[5], commands
        assert "up -d --remove-orphans" in commands[6], commands
        assert "Lava is optional" in commands[7] or "inspect --format" in commands[7], (
            commands
        )

    def test_remote_deploy_blocks_when_stale_stack_cleanup_fails(self) -> None:

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="cleanup-failure",
            display_name="Cleanup Failure",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        with (
            mock.patch.object(
                executor,
                "_resolve_remote_deploy_dir",
                return_value="/home/nmtk/nmtk-deploy",
            ),
            mock.patch.object(executor, "_ensure_engine_installed"),
            mock.patch.object(executor, "_prepare_podman_runtime"),
            mock.patch.object(executor, "_copy_manifests_to_remote"),
            mock.patch.object(executor, "_init_remote_secrets"),
            mock.patch.object(
                executor,
                "_ssh_run",
                side_effect=[
                    None,
                    None,
                    None,
                    RuntimeError("old compose project is already gone"),
                ],
            ),
            mock.patch.object(executor, "_health_check"),
            mock.patch.object(executor, "_jupyter_health_check"),
            self.assertRaises(RuntimeError) as context,
        ):
            executor._deploy_remote(target, lambda *_args: None)

        assert "could not be reconciled safely" in str(context.exception)

    def test_remote_port_conflict_error_names_port_and_safe_recovery(self) -> None:

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="port-conflict",
            display_name="Port Conflict",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        conflict = RuntimeError(
            "Remote command failed: rootlessport listen tcp 0.0.0.0:8012: "
            "bind: address already in use"
        )

        with (
            mock.patch.object(
                executor,
                "_resolve_remote_deploy_dir",
                return_value="/home/nmtk/nmtk-deploy",
            ),
            mock.patch.object(executor, "_ensure_engine_installed"),
            mock.patch.object(executor, "_prepare_podman_runtime"),
            mock.patch.object(executor, "_copy_manifests_to_remote"),
            mock.patch.object(executor, "_init_remote_secrets"),
            mock.patch.object(executor, "_remote_port_owner_probe"),
            mock.patch.object(executor, "_collect_remote_startup_diagnostics"),
            mock.patch.object(
                executor,
                "_ssh_run",
                side_effect=[None, None, None, None, None, conflict],
            ),
            self.assertRaises(RuntimeError) as context,
        ):
            executor._deploy_remote(target, lambda *_args: None)

        message = str(context.exception)
        assert "host port 8012" in message, message
        assert "unrelated service" in message, message
        assert "fuser" not in message, message

    def test_copy_manifests_password_not_in_cmdline(self) -> None:
        """The manifest copy must ship only the compose files + monitoring/,
        and carry the SSH password via SSHPASS env, never in argv."""
        import tempfile

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "docker-compose.yml").write_text("services: {}\n")
            (root / "docker-compose.prod.yml").write_text("services: {}\n")
            (root / "docker-compose.remote.yml").write_text("services: {}\n")
            (root / "monitoring").mkdir()

            target = DeploymentTarget(
                id="copy-pwd",
                display_name="Copy Pwd",
                target_type="remote_host",
                mode="docker",
                host="192.0.2.2",
                auth_mode="ssh_password",
                secret_refs={"sshPassword": "ref:my-secret"},
            )
            executor = DockerDeploymentExecutor(
                repo_root=root,
                secret_resolver=lambda _ref: "supersecret",
            )

            calls: list[dict] = []

            def fake_run(cmd: list[str], **kwargs: object) -> mock.Mock:
                calls.append({"cmd": cmd, "env": kwargs.get("env", {})})
                return mock.Mock(returncode=0, stdout="", stderr="")

            with (
                mock.patch(
                    "nmtk.launcher_control.deployment_executors.subprocess.run",
                    side_effect=fake_run,
                ),
                mock.patch.object(executor, "_ssh_key_context") as mock_ctx,
            ):
                mock_ctx.return_value.__enter__ = mock.Mock(return_value=None)
                mock_ctx.return_value.__exit__ = mock.Mock(return_value=False)
                executor._copy_manifests_to_remote(target, "/home/nmtk/nmtk-deploy")

        assert calls, "expected rsync to be invoked"
        cmd_str = " ".join(calls[0]["cmd"])
        env = calls[0]["env"]
        assert "supersecret" not in cmd_str, cmd_str
        assert env.get("SSHPASS") == "supersecret", list(env.keys())
        assert "sshpass -e" in cmd_str, cmd_str
        assert (
            "docker-compose.yml" in cmd_str
            and "docker-compose.prod.yml" in cmd_str
            and "docker-compose.remote.yml" in cmd_str
        ), cmd_str
        assert "monitoring" in cmd_str, cmd_str

    def test_copy_manifests_missing_raises_actionable_error(self) -> None:
        """If the compose files aren't present (bundle didn't ship them),
        the error must say so rather than silently copying nothing."""
        import tempfile

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        with tempfile.TemporaryDirectory() as tmp:
            target = DeploymentTarget(
                id="copy-missing",
                display_name="Copy Missing",
                target_type="remote_host",
                mode="docker",
                host="192.0.2.2",
                auth_mode="none",
            )
            executor = DockerDeploymentExecutor(repo_root=Path(tmp))
            with self.assertRaises(RuntimeError) as ctx:
                executor._copy_manifests_to_remote(target, "/home/nmtk/nmtk-deploy")

        assert "manifests not found" in str(ctx.exception).lower(), str(ctx.exception)
