"""Launcher control service tests: TestLauncherPynqProvisioning."""

from typing import Any
import json
import nmtk.launcher_control.server as launcher_server
from unittest import mock
from base import LauncherControlServiceTestBase, _stage_overlay_package


class TestLauncherPynqProvisioning(LauncherControlServiceTestBase):
    def test_read_remote_pynq_install_status_decodes_machine_readable_result(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with mock.patch.object(
            self.state,
            "_run_ssh",
            return_value=json.dumps({"installMode": "user-space", "message": "fallback"}),
        ):
            status = self.state._read_remote_pynq_install_status(self.state._get_pynq_board(board["id"]))

        self.assertEqual(status["installMode"], "user-space")

    def test_restart_pynq_runtime_returns_warning_for_user_space_install(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with mock.patch.object(
            self.state,
            "_read_remote_pynq_install_status",
            return_value={"installMode": "user-space"},
        ):
            result = self.state.restart_pynq_runtime(board["id"])

        self.assertEqual(result["board"]["state"], "degraded_optional_capability")
        self.assertIn("user space", result["warning"])
        self.assertIn("Enable passwordless sudo for 'xilinx'", result["warning"])
        self.assertIn("re-run Provision Runtime", result["warning"])

    def test_restart_pynq_runtime_waits_for_health_before_preflight_when_systemd_managed(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        events: list[str] = []

        def record_run_ssh(*_args: Any, **_kwargs: Any) -> str:
            events.append("ssh")
            return ""

        def record_wait(*_args: Any, **_kwargs: Any) -> None:
            events.append("wait")

        def record_preflight(*_args: Any, **_kwargs: Any) -> dict[str, Any]:
            events.append("preflight")
            return {"board": {"state": "ready"}}

        with (
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(self.state, "_run_ssh", side_effect=record_run_ssh),
            mock.patch.object(
                self.state,
                "_wait_for_board_agent_health",
                side_effect=record_wait,
            ) as wait_for_health,
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                side_effect=record_preflight,
            ) as fetch_preflight,
        ):
            result = self.state.restart_pynq_runtime(board["id"])

        wait_for_health.assert_called_once()
        fetch_preflight.assert_called_once_with(
            board["id"],
            request_timeout=launcher_server.DEFAULT_PYNQ_PREFLIGHT_TIMEOUT_SECONDS,
        )
        self.assertEqual(events, ["ssh", "wait", "preflight"])
        self.assertEqual(result["board"]["state"], "ready")

    def test_describe_pynq_preflight_reports_overlay_missing_actionably(self) -> None:
        description = launcher_server._describe_pynq_preflight(
            {
                "preflight_status": "failed",
                "preflight_message": "Install Overlay next. Checked bitstream path: /tmp/snn_overlay.bit.",
                "overlay_assets": {"ready_for_hardware": False},
            }
        )

        self.assertIn("overlay assets missing", description)
        self.assertIn("/tmp/snn_overlay.bit", description)

    def test_describe_pynq_preflight_surfaces_runtime_probe_context(self) -> None:
        description = launcher_server._describe_pynq_preflight(
            {
                "preflight_status": "failed",
                "preflight_message": (
                    "Hardware runtime assets are present, but the board cannot open a usable "
                    "PYNQ device yet. Runtime probe failed: Bitstream not found: "
                    "snn_overlay.bit. Checked bitstream path: "
                    "/home/xilinx/.local/share/neurochip-pynq-agent/overlays/snn_overlay.bit."
                ),
                "overlay_assets": {"ready_for_hardware": True},
            }
        )

        self.assertIn("Bitstream not found", description)
        self.assertIn("/home/xilinx/.local/share/neurochip-pynq-agent/overlays/snn_overlay.bit", description)

    def test_provision_pynq_board_reports_install_status(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with (
            mock.patch.object(self.state, "_build_local_pynq_bundle"),
            mock.patch.object(self.state, "_run_ssh"),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "user-space"},
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                return_value={"board": {"state": "degraded_optional_capability"}},
            ),
        ):
            result = self.state.provision_pynq_board(board["id"])

        self.assertEqual(result["installStatus"]["installMode"], "user-space")
        self.assertEqual(result["board"]["state"], "degraded_optional_capability")
        self.assertIn(
            "Enable passwordless sudo for 'xilinx'",
            result["board"]["lastPreflightMessage"],
        )
        self.assertIn(
            "re-run Provision Runtime",
            result["board"]["lastPreflightMessage"],
        )

    def test_provision_pynq_board_tails_runtime_log_when_install_script_fails(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with (
            mock.patch.object(self.state, "_build_local_pynq_bundle"),
            mock.patch.object(
                self.state,
                "_run_ssh",
                side_effect=["", RuntimeError("install script failed on remote host")],
            ),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(self.state, "_emit_runtime_log_tail") as emit_runtime_log_tail,
        ):
            result = self.state.provision_pynq_board(board["id"])

        emit_runtime_log_tail.assert_called_once()
        self.assertEqual(emit_runtime_log_tail.call_args.args[1], {})
        self.assertEqual(result["error"], "install script failed on remote host")
        self.assertEqual(result["board"]["state"], "provision_failed")
        self.assertEqual(
            result["board"]["lastPreflightMessage"],
            "install script failed on remote host",
        )

    def test_install_pynq_overlay_assets_reports_missing_staged_package(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with (
            mock.patch.object(self.state, "_run_ssh") as run_ssh,
            mock.patch.object(self.state, "_run_scp") as run_scp,
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        self.assertEqual(result["board"]["state"], "overlay_missing")
        # The overlay ships with the backend, so a missing one is a broken
        # install, not a step the user skipped — the message must not send them
        # off to synthesise a bitstream.
        self.assertIn(
            "ships with the backend is missing",
            result["board"]["lastPreflightMessage"],
        )
        self.assertIn(
            str(self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"),
            result["board"]["lastPreflightMessage"],
        )
        self.assertFalse(result["localOverlayPackage"]["ready"])
        run_ssh.assert_not_called()
        run_scp.assert_not_called()

    def test_overlay_package_falls_back_to_shipped_artifact_dir(self) -> None:
        """The shipped image has no Neurochip source tree, only artifacts.

        `_neurochip_module_root()` resolves to a path the launcher-control image
        never contains, so without this fallback Install Overlay reported
        `overlay_missing` forever on every containerised backend — the overlay
        the image does carry was simply never looked at.
        """
        artifact_root = self.repo_root / "artifacts" / "neurochip"
        _stage_overlay_package(artifact_root / "overlay_staging" / "pynq_z2")

        with mock.patch.dict(
            "os.environ",
            {"NMTK_NEUROCHIP_ARTIFACT_DIR": str(artifact_root)},
        ):
            package = self.state._inspect_local_pynq_overlay_package()

        self.assertTrue(package["ready"])
        self.assertEqual(
            package["stagingDir"],
            str((artifact_root / "overlay_staging" / "pynq_z2").resolve()),
        )

    def test_overlay_package_prefers_module_root_over_shipped_copy(self) -> None:
        """A locally synthesised overlay must beat the one baked into the image."""
        module_staging = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        artifact_root = self.repo_root / "artifacts" / "neurochip"
        _stage_overlay_package(module_staging)
        _stage_overlay_package(artifact_root / "overlay_staging" / "pynq_z2")

        with mock.patch.dict(
            "os.environ",
            {"NMTK_NEUROCHIP_ARTIFACT_DIR": str(artifact_root)},
        ):
            package = self.state._inspect_local_pynq_overlay_package()

        self.assertTrue(package["ready"])
        self.assertEqual(package["stagingDir"], str(module_staging.resolve()))

    def test_install_pynq_overlay_assets_uploads_staged_package(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        staging_dir.mkdir(parents=True, exist_ok=True)
        bitstream = staging_dir / "snn_overlay.bit"
        hwh = staging_dir / "snn_overlay.hwh"
        manifest = staging_dir / "overlay_manifest.json"
        bitstream.write_bytes(b"bitstream")
        hwh.write_text("<hwh/>", encoding="utf-8")
        manifest.write_text(
            json.dumps(
                {
                    "overlay_id": "snn_overlay_v1",
                    "overlay_version": "1.0.1",
                    "target_part": "xc7z020clg400-1",
                    "supported_neuron_models": ["LIF"],
                    "supported_weight_bit_widths": [8],
                    "max_neurons": 256,
                    "max_synapses": 15360,
                    "max_populations": 2,
                    "dma_ip_name": "axi_dma_0",
                    "snn_ip_name": "snn_engine_0",
                    "register_map": {
                        "base_address": 1073741824,
                        "control_reg_offset": 0,
                        "status_reg_offset": 4,
                        "population_count_offset": 8,
                        "input_neuron_count_offset": 12,
                        "output_neuron_count_offset": 16,
                        "timestep_count_offset": 20,
                        "threshold_base_offset": 256,
                        "neuron_base_offset": 256,
                        "weight_base_offset": 4096,
                        "dma_channel": "axi_dma_0",
                        "input_buffer_addr": 0,
                        "output_buffer_addr": 0,
                        "timestep_us": 1000,
                    },
                    "weight_layout": {
                        "format": "int8_dense_row_major_word_mmio",
                        "storage": "mmio",
                        "base_offset": 4096,
                        "stride_bytes": 4,
                        "max_entries": 15360,
                    },
                    "threshold_layout": {
                        "format": "float32_per_population",
                        "storage": "mmio",
                        "base_offset": 256,
                        "stride_bytes": 4,
                        "max_entries": 2,
                    },
                },
                indent=2,
            ),
            encoding="utf-8",
        )

        with (
            mock.patch.object(self.state, "_run_ssh") as run_ssh,
            mock.patch.object(self.state, "_run_scp") as run_scp,
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(self.state, "_restart_user_space_agent") as restart_agent,
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                return_value={"board": {"state": "ready"}},
            ),
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        run_ssh.assert_called_once_with(
            self.state._get_pynq_board(board["id"]),
            f"mkdir -p {board['remoteOverlayDir']}",
        )
        restart_agent.assert_not_called()
        self.assertEqual(run_scp.call_count, 3)
        self.assertEqual(run_scp.call_args_list[0].args[1].resolve(), bitstream.resolve())
        self.assertEqual(
            run_scp.call_args_list[0].args[2],
            f"{board['remoteOverlayDir']}/snn_overlay.bit",
        )
        self.assertEqual(run_scp.call_args_list[1].args[1].resolve(), hwh.resolve())
        self.assertEqual(
            run_scp.call_args_list[1].args[2],
            f"{board['remoteOverlayDir']}/snn_overlay.hwh",
        )
        self.assertEqual(run_scp.call_args_list[2].args[1].resolve(), manifest.resolve())
        self.assertEqual(
            run_scp.call_args_list[2].args[2],
            f"{board['remoteOverlayDir']}/overlay_manifest.json",
        )
        self.assertTrue(result["localOverlayPackage"]["ready"])
        self.assertNotIn("overlayRestartWarning", result)

    def test_install_pynq_overlay_assets_restarts_user_space_agent(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(staging_dir)

        with (
            mock.patch.object(self.state, "_run_ssh"),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "user-space"},
            ),
            mock.patch.object(self.state, "_restart_user_space_agent") as restart_agent,
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                return_value={"board": {"state": "degraded_optional_capability"}},
            ),
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        restart_agent.assert_called_once()
        self.assertNotIn("overlayRestartWarning", result)

    def test_install_pynq_overlay_assets_returns_warning_when_agent_restart_times_out(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(staging_dir)

        emissions: list[tuple[str, bool]] = []

        def record_emit(_board: Any, message: str, *, stderr: bool = False) -> None:
            emissions.append((message, stderr))

        with (
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_run_ssh",
                side_effect=[None, "line1\nline2\n"],
            ),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={
                    "installMode": "user-space",
                    "runtimeLogPath": "/home/xilinx/.local/share/neurochip-pynq-agent/runtime.log",
                },
            ),
            mock.patch.object(
                self.state,
                "_restart_user_space_agent",
                side_effect=RuntimeError("agent did not become healthy within 60s"),
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                return_value={"board": {"state": "degraded_optional_capability"}},
            ),
            mock.patch.object(self.state, "_emit_pynq_terminal_log", side_effect=record_emit),
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        self.assertIn("overlayRestartWarning", result)
        self.assertIn("agent did not become healthy", result["overlayRestartWarning"])
        tail_messages = [msg for msg, _stderr in emissions if msg.startswith("runtime.log | ")]
        self.assertEqual(
            tail_messages,
            ["runtime.log | line1", "runtime.log | line2"],
        )
        summary_messages = [
            msg for msg, _stderr in emissions if "restart did not become healthy" in msg
        ]
        self.assertTrue(summary_messages, "expected a summary line about restart failure")

    def test_install_pynq_overlay_assets_degrades_when_readiness_refresh_fails_after_upload(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(staging_dir)

        emissions: list[tuple[str, bool]] = []

        def record_emit(_board: Any, message: str, *, stderr: bool = False) -> None:
            emissions.append((message, stderr))

        with (
            mock.patch.object(self.state, "_run_ssh"),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "user-space"},
            ),
            mock.patch.object(
                self.state,
                "_restart_user_space_agent",
                side_effect=RuntimeError("agent did not become healthy within 60s"),
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                side_effect=RuntimeError("connection refused"),
            ),
            mock.patch.object(self.state, "_emit_pynq_terminal_log", side_effect=record_emit),
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        self.assertEqual(result["board"]["state"], "degraded_optional_capability")
        self.assertEqual(result["board"]["lastPreflightStatus"], "degraded")
        self.assertEqual(
            result["board"]["lastPreflightMessage"],
            launcher_server.PYNQ_OVERLAY_UPLOAD_RECOVERY_MESSAGE,
        )
        self.assertIn("overlayRestartWarning", result)
        self.assertIn("agent did not become healthy", result["overlayRestartWarning"])
        duplicate_refresh_messages = [
            msg for msg, _stderr in emissions if "readiness refresh after overlay upload did not complete" in msg
        ]
        self.assertEqual(
            duplicate_refresh_messages,
            [],
            "restart failure should remain the single summary line for this recovery path",
        )

    def test_install_pynq_overlay_assets_preserves_explicit_overlay_missing_preflight(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(staging_dir)

        with (
            mock.patch.object(self.state, "_run_ssh"),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                return_value={
                    "board": {
                        "state": "overlay_missing",
                        "lastPreflightStatus": "failed",
                        "lastPreflightMessage": "Install Overlay next.",
                    }
                },
            ),
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        self.assertEqual(result["board"]["state"], "overlay_missing")
        self.assertNotIn("overlayRestartWarning", result)

    def test_install_pynq_overlay_assets_preserves_explicit_preflight_failure(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(staging_dir)

        with (
            mock.patch.object(self.state, "_run_ssh"),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                return_value={
                    "board": {
                        "state": "preflight_failed",
                        "lastPreflightStatus": "failed",
                        "lastPreflightMessage": "Runtime probe failed: No Devices Found.",
                    }
                },
            ),
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        self.assertEqual(result["board"]["state"], "preflight_failed")
        self.assertNotIn("overlayRestartWarning", result)

    def test_inspect_local_pynq_overlay_package_validates_manifest_without_importing_neurochip(
        self,
    ) -> None:
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(staging_dir)
        manifest_path = staging_dir / "overlay_manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["weight_layout"]["stride_bytes"] = 8
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

        status = self.state._inspect_local_pynq_overlay_package()

        self.assertFalse(status["ready"])
        self.assertFalse(status["manifestValid"])
        self.assertIn(
            "weight_layout.stride_bytes must match overlay-v1 word-MMIO stride",
            "\n".join(status["issues"]),
        )
