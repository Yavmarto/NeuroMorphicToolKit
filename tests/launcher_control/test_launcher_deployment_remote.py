"""Launcher control service tests: remote deployment transport (ssh, secrets, compose commands, diagnostics, cleanup)."""

import io
from pathlib import Path
from unittest import mock

from base import LauncherControlServiceTestBase


class TestLauncherDeploymentRemote(LauncherControlServiceTestBase):
    def test_init_remote_secrets_quotes_deploy_dir(self) -> None:
        """deploy_dir with shell metacharacters must not be passed raw to the SSH command."""
        from unittest import mock

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="remote-inject",
            display_name="Remote Inject",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.1",
            auth_mode="none",
            install_root="/opt/nmtk; echo INJECTED",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        captured_cmds: list[str] = []

        def fake_ssh_run(tgt: object, remote_cmd: str, timeout: int = 600) -> None:
            captured_cmds.append(remote_cmd)

        with mock.patch.object(executor, "_ssh_run", side_effect=fake_ssh_run):
            executor._init_remote_secrets(target, "/opt/nmtk; echo INJECTED")

        assert captured_cmds, "expected _ssh_run to be called"
        cmd = captured_cmds[0]
        # shlex.quote wraps the path in single quotes, neutralising the injection
        assert "echo INJECTED" not in cmd.split("'")[0], (
            f"shell injection not neutralised; raw cmd: {cmd!r}"
        )

    def test_init_remote_secrets_clean_path(self) -> None:
        """A clean deploy_dir produces a valid shell command without altering the path."""
        from unittest import mock

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="remote-clean",
            display_name="Remote Clean",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.1",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        captured_cmds: list[str] = []

        def fake_ssh_run(tgt: object, remote_cmd: str, timeout: int = 600) -> None:
            captured_cmds.append(remote_cmd)

        with mock.patch.object(executor, "_ssh_run", side_effect=fake_ssh_run):
            executor._init_remote_secrets(target, "/opt/nmtk")

        assert captured_cmds, "expected _ssh_run to be called"
        cmd = captured_cmds[0]
        assert "/opt/nmtk" in cmd, f"deploy_dir not found in cmd: {cmd!r}"
        assert "GRAFANA_ADMIN_PASSWORD" in cmd, f"secret setup not in cmd: {cmd!r}"

    def test_init_remote_secrets_path_with_spaces(self) -> None:
        """A deploy_dir containing spaces must be quoted so the shell treats it as one token."""
        from unittest import mock

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="remote-spaces",
            display_name="Remote Spaces",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.1",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        captured_cmds: list[str] = []

        def fake_ssh_run(tgt: object, remote_cmd: str, timeout: int = 600) -> None:
            captured_cmds.append(remote_cmd)

        with mock.patch.object(executor, "_ssh_run", side_effect=fake_ssh_run):
            executor._init_remote_secrets(target, "/opt/my deploy dir")

        assert captured_cmds, "expected _ssh_run to be called"
        cmd = captured_cmds[0]
        assert "'/opt/my deploy dir'" in cmd, (
            f"expected path with spaces to be single-quoted; cmd: {cmd!r}"
        )

    @staticmethod
    def _fake_rsync_popen(returncode: int = 0, output_lines: "list[str] | None" = None):
        """Build a fake Popen double for the streaming _ssh_run reader loop.

        `proc.stdout` is a real io.StringIO so the reader thread's
        `iter(proc.stdout.readline, "")` behaves exactly like a real pipe
        that's already fully written and closed -- it drains immediately.
        """
        proc = mock.Mock()
        proc.stdout = io.StringIO("".join(f"{line}\n" for line in (output_lines or [])))
        proc.poll.return_value = returncode
        proc.wait.return_value = returncode
        return proc

    def test_ssh_run_streams_output_to_log_channel(self) -> None:
        """docker compose pull/up output must stream line-by-line to the
        log channel (self._log), not be discarded like the old blocking
        subprocess.run did on success."""
        from unittest import mock

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="ssh-stream",
            display_name="Ssh Stream",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.9",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        collected: list[str] = []
        executor._log = collected.append

        def fake_popen(cmd: list[str], **kwargs: object) -> mock.Mock:
            return self._fake_rsync_popen(
                output_lines=["#1 building", "#2 exporting", "#3 done"]
            )

        with (
            mock.patch(
                "nmtk.launcher_control.deployment_executors.subprocess.Popen",
                side_effect=fake_popen,
            ),
            mock.patch.object(executor, "_ssh_key_context") as mock_ctx,
        ):
            mock_ctx.return_value.__enter__ = mock.Mock(return_value=None)
            mock_ctx.return_value.__exit__ = mock.Mock(return_value=False)
            executor._ssh_run(target, "docker compose build")

        assert collected, "expected _ssh_run to forward output to the log channel"
        assert collected[0] == "$ docker compose build", collected
        # The final line is always flushed so the last step stays visible.
        assert collected[-1] == "#3 done", collected
        assert set(collected[1:]).issubset({"#1 building", "#2 exporting", "#3 done"})

    def test_ssh_run_failure_raises_with_output_tail(self) -> None:
        """A non-zero remote command must raise with a tail of its output."""
        from unittest import mock

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="ssh-fail",
            display_name="Ssh Fail",
            target_type="remote_host",
            mode="docker",
            host="192.0.2.10",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        def fake_popen(cmd: list[str], **kwargs: object) -> mock.Mock:
            return self._fake_rsync_popen(
                returncode=1, output_lines=["step ok", "ERROR: build failed"]
            )

        with (
            mock.patch(
                "nmtk.launcher_control.deployment_executors.subprocess.Popen",
                side_effect=fake_popen,
            ),
            mock.patch.object(executor, "_ssh_key_context") as mock_ctx,
        ):
            mock_ctx.return_value.__enter__ = mock.Mock(return_value=None)
            mock_ctx.return_value.__exit__ = mock.Mock(return_value=False)
            with self.assertRaises(RuntimeError) as ctx:
                executor._ssh_run(target, "docker compose build")

        assert "build failed" in str(ctx.exception), str(ctx.exception)

    def test_remote_compose_cmd_uses_prod_files_and_env(self) -> None:
        """The remote docker compose command must select both compose files
        and set the env the prod stack needs (mirrors `make deploy-prod`)."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="compose-cmd",
            display_name="Compose Cmd",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
        )
        cmd = executor._remote_compose_cmd("/home/nmtk/nmtk-deploy", target, "pull")

        assert (
            "-f docker-compose.yml -f docker-compose.prod.yml "
            "-f docker-compose.remote.yml"
        ) in cmd, cmd
        assert "pull" in cmd, cmd
        assert "LAUNCHER_CONTROL_PORT=8090" in cmd, cmd
        assert "JUPYTER_PUBLIC_URL=" in cmd and "203.0.113.34:8008/lab" in cmd, cmd
        assert "nmtk-deploy" in cmd, cmd
        # No source build anywhere in the source-free flow.
        assert "build" not in cmd, cmd
        # Docker path activates the docker group via `sg` for a just-added membership.
        assert "sg docker" in cmd, cmd

    def test_remote_compose_cmd_uses_selected_image_tag(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="compose-tag",
            display_name="Compose Tag",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
            image_tag="v2026.07.24",
        )

        cmd = executor._remote_compose_cmd("/home/nmtk/nmtk-deploy", target, "pull")

        assert "NMTK_IMAGE_TAG=v2026.07.24" in cmd, cmd
        assert executor._image_tag(target) == "v2026.07.24"
        target.image_tag = "bad tag; rm -rf /"
        assert executor._image_tag(target) == "latest"

    def test_compose_contract_does_not_gate_suite_api_on_lava_health(self) -> None:
        compose = (
            Path(__file__).resolve().parents[2] / "docker-compose.yml"
        ).read_text(encoding="utf-8")
        suite_block = compose.split("  neurosense-hw-worker:", 1)[0]
        assert "condition: service_started" in suite_block
        assert "required: false" in suite_block
        assert "condition: service_healthy" not in suite_block
        # The hardware worker starts independently; Lava failures are reported
        # by its runtime routes instead of blocking the core stack.
        neurochip_block = compose.split("  neurochip-hw-worker:", 1)[1].split(
            "\n  lava-backend:", 1
        )[0]
        assert "condition: service_started" in neurochip_block
        assert "required: false" in neurochip_block
        assert "condition: service_healthy" not in neurochip_block

    def test_remote_provider_preflight_checks_engine_and_merged_config(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="provider-pf",
            display_name="Provider PF",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
            container_engine="podman",
        )
        commands: list[str] = []

        with mock.patch.object(
            executor,
            "_ssh_run",
            side_effect=lambda _target, command, timeout=600: commands.append(command),
        ):
            executor._remote_provider_preflight(target, "/home/nmtk/nmtk-deploy")

        assert len(commands) == 2
        assert "podman info" in commands[0], commands
        assert "podman compose version" in commands[0], commands
        assert "config --quiet" in commands[1], commands

    def test_legacy_compose_project_uses_deploy_directory_basename(self) -> None:
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        assert (
            DockerDeploymentExecutor._legacy_compose_project("/home/nmtk/nmtk-deploy")
            == "nmtk-deploy"
        )
        assert DockerDeploymentExecutor._legacy_compose_project("/home/nmtk/nmtk") == ""

    def test_stale_cleanup_is_label_scoped_across_runtimes(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="cleanup-labels",
            display_name="Cleanup Labels",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
            container_engine="podman",
        )
        commands: list[str] = []

        with mock.patch.object(
            executor,
            "_ssh_run",
            side_effect=lambda _target, command, timeout=600: commands.append(command),
        ):
            executor._remote_cleanup_stale_projects(target, "/home/nmtk/nmtk-deploy")

        assert len(commands) == 1
        command = commands[0]
        assert "for runtime in podman docker" in command
        assert "com.docker.compose.project=$project" in command
        assert "io.podman.compose.project=$project" in command
        assert "nmtk-deploy" in command
        assert "{{.ID}} {{.Names}}" in command
        assert "jupyter-server" in command
        assert "fuser" not in command
        assert "volume" not in command

    def test_factory_reset_cleanup_removes_only_labelled_volumes(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="cleanup-volumes",
            display_name="Cleanup Volumes",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
        )
        commands: list[str] = []

        with mock.patch.object(
            executor,
            "_ssh_run",
            side_effect=lambda _target, command, timeout=600: commands.append(command),
        ):
            executor._remote_cleanup_stale_projects(
                target,
                "/home/nmtk/nmtk-deploy",
                remove_volumes=True,
            )

        command = commands[0]
        assert "volume ls -q --filter" in command
        assert "volume rm -f" in command
        assert "volume prune" not in command

    def test_port_owner_probe_reports_client_ports_and_compose_labels(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="port-owner",
            display_name="Port Owner",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
        )
        commands: list[str] = []

        with mock.patch.object(
            executor,
            "_ssh_run",
            side_effect=lambda _target, command, timeout=600: commands.append(command),
        ):
            executor._remote_port_owner_probe(target)

        assert len(commands) == 1
        command = commands[0]
        assert "for port in 9000 8090 8008" in command
        assert "com.docker.compose.project" in command
        assert "io.podman.compose.project" in command
        assert "ss -ltnp" in command

    def test_startup_diagnostics_include_compose_state_and_lava_logs(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="diagnostics",
            display_name="Diagnostics",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
            container_engine="podman",
        )
        commands: list[str] = []
        logs: list[str] = []
        executor._log = logs.append

        with mock.patch.object(
            executor,
            "_ssh_run",
            side_effect=lambda _target, command, timeout=600: commands.append(command),
        ):
            executor._collect_remote_startup_diagnostics(
                target, "/home/nmtk/nmtk-deploy"
            )

        assert any(" ps -a" in command for command in commands), commands
        assert any("logs --tail=100 lava-backend" in command for command in commands), (
            commands
        )
        assert any("inspect --format" in command for command in commands), commands
        assert any("probe_status" in command for command in commands), commands
        assert any("config --format json" in command for command in commands), commands
        assert any("health diagnostics" in line for line in logs), logs

    def test_readiness_diagnostics_include_suite_api_logs_and_direct_probe(
        self,
    ) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="readiness-diagnostics",
            display_name="Readiness Diagnostics",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
            backend_port=9010,
            container_engine="podman",
        )
        commands: list[str] = []
        logs: list[str] = []
        executor._log = logs.append

        with mock.patch.object(
            executor,
            "_ssh_run",
            side_effect=lambda _target, command, timeout=600: commands.append(command),
        ):
            executor._collect_remote_readiness_diagnostics(
                target, "/home/nmtk/nmtk-deploy"
            )

        assert any("logs --tail=200 suite_api" in command for command in commands)
        probe_command = commands[-1]
        assert "127.0.0.1:9010/api/suite/health" in probe_command
        assert "host listener tcp/9010" in probe_command
        assert "inspect --format" in probe_command
        assert any("[nmtk-suite-api]" in line for line in logs)

    def test_remote_readiness_timeout_collects_diagnostics_before_raising(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="readiness-timeout",
            display_name="Readiness Timeout",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        diagnostics = mock.Mock()

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
            mock.patch.object(executor, "_remote_provider_preflight"),
            mock.patch.object(executor, "_remote_port_owner_probe"),
            mock.patch.object(executor, "_remote_cleanup_stale_projects"),
            mock.patch.object(executor, "_ssh_run"),
            mock.patch.object(
                executor,
                "_health_check",
                side_effect=RuntimeError(
                    "Backend health check timed out at http://203.0.113.34:9000/api/suite/health: timed out"
                ),
            ),
            mock.patch.object(
                executor,
                "_collect_remote_readiness_diagnostics",
                diagnostics,
            ),
            self.assertRaises(RuntimeError) as context,
        ):
            executor._deploy_remote(target, lambda *_args: None)

        diagnostics.assert_called_once_with(target, "/home/nmtk/nmtk-deploy")
        assert "readiness diagnostics were collected" in str(context.exception)

    def test_remote_jupyter_failure_collects_diagnostics_and_blocks_ready(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="jupyter-timeout",
            display_name="Jupyter Timeout",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        diagnostics = mock.Mock()

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
            mock.patch.object(executor, "_remote_provider_preflight"),
            mock.patch.object(executor, "_remote_port_owner_probe"),
            mock.patch.object(executor, "_remote_cleanup_stale_projects"),
            mock.patch.object(executor, "_ssh_run"),
            mock.patch.object(executor, "_health_check"),
            mock.patch.object(
                executor,
                "_jupyter_health_check",
                side_effect=RuntimeError("Jupyter readiness timed out"),
            ),
            mock.patch.object(
                executor, "_collect_remote_jupyter_diagnostics", diagnostics
            ),
            self.assertRaises(RuntimeError) as context,
        ):
            executor._deploy_remote(target, lambda *_args: None)

        diagnostics.assert_called_once_with(target, "/home/nmtk/nmtk-deploy")
        assert "degraded optional capability: Jupyter" in str(context.exception)

    def test_jupyter_readiness_checks_internal_and_public_endpoints(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="jupyter-ready",
            display_name="Jupyter Ready",
            target_type="remote_host",
            mode="docker",
            host="203.0.113.34",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        class Response:
            status = 200

            def read(self) -> bytes:
                return b'{"status":"ok","module":"jupyter"}'

            def __enter__(self):
                return self

            def __exit__(self, *_args) -> None:
                return None

        with mock.patch(
            "nmtk.launcher_control.deployment_executors.urllib.request.urlopen",
            side_effect=[Response(), Response()],
        ) as urlopen:
            executor._jupyter_health_check(target)

        calls = [str(call.args[0]) for call in urlopen.call_args_list]
        assert calls == [
            "http://203.0.113.34:9000/api/jupyter/health",
            "http://203.0.113.34:8008/api/status",
        ]
