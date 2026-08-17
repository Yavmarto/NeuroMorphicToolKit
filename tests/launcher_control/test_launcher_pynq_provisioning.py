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

    def test_restart_pynq_runtime_restarts_user_space_agent_and_refreshes_preflight(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        refreshed = {
            "board": {
                "state": "overlay_missing",
                "lastPreflightMessage": "Install overlay next.",
            }
        }
        with (
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "user-space"},
            ),
            mock.patch.object(self.state, "_restart_user_space_agent") as restart,
            mock.patch.object(
                self.state,
                "_refresh_pynq_board_preflight",
                return_value=refreshed,
            ) as refresh,
        ):
            result = self.state.restart_pynq_runtime(board["id"])

        restart.assert_called_once()
        refresh.assert_called_once_with(
            board["id"], stage="user-space runtime restart"
        )
        self.assertEqual(result["board"]["state"], "overlay_missing")
        self.assertEqual(result["installStatus"]["installMode"], "user-space")

    def test_preflight_with_missing_overlay_stays_actionable_when_degraded(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        updated = self.state._apply_preflight_to_board(
            board["id"],
            {
                "preflight_status": "degraded",
                "preflight_message": "Simulator fallback active.",
                "overlay_assets": {"ready_for_hardware": False},
            },
        )

        self.assertEqual(updated["state"], "overlay_missing")

    def test_preflight_records_the_overlay_version_the_board_reports(self) -> None:
        """Otherwise the app says "Overlay: Not installed" for a loaded overlay."""
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        updated = self.state._apply_preflight_to_board(
            board["id"],
            {
                "preflight_status": "ok",
                "preflight_message": "Hardware runtime and canonical overlay assets are ready.",
                "overlay_assets": {
                    "ready_for_hardware": True,
                    "overlay_id": "snn_overlay_v2",
                    "overlay_version": "2.0.0",
                },
            },
        )

        self.assertEqual(updated["state"], "ready")
        self.assertEqual(updated["overlayVersion"], "2.0.0")

    def test_preflight_without_an_overlay_version_keeps_the_stored_one(self) -> None:
        """A preflight that could not read the manifest is not a removal."""
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        self.state._update_pynq_board_fields(board["id"], overlayVersion="2.0.0")

        updated = self.state._apply_preflight_to_board(
            board["id"],
            {
                "preflight_status": "failed",
                "preflight_message": "Runtime probe failed.",
                "overlay_assets": {"ready_for_hardware": True},
            },
        )

        self.assertEqual(updated["overlayVersion"], "2.0.0")

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

        def apply_overlay_missing_preflight(
            *_args: Any, **_kwargs: Any
        ) -> dict[str, Any]:
            updated = self.state._update_pynq_board_fields(
                board["id"],
                state="overlay_missing",
                lastPreflightStatus="failed",
                lastPreflightMessage="Install overlay next.",
            )
            return {"board": launcher_server._serialize_pynq_board(updated)}

        def ssh(_board: Any, command: str) -> str:
            # This board grants no administrator access, so provisioning cannot
            # promote the runtime to a privileged service and the user-space
            # install is what the user is told about.
            if command.startswith("sudo -n"):
                raise RuntimeError("sudo: a terminal is required to read the password")
            return ""

        with (
            mock.patch.object(self.state, "_build_local_pynq_bundle"),
            mock.patch.object(self.state, "_run_ssh", side_effect=ssh),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "user-space"},
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                side_effect=apply_overlay_missing_preflight,
            ),
        ):
            result = self.state.provision_pynq_board(board["id"])

        self.assertEqual(result["installStatus"]["installMode"], "user-space")
        self.assertEqual(result["board"]["state"], "overlay_missing")
        self.assertIn(
            "Install the overlay now",
            result["board"]["lastPreflightMessage"],
        )
        self.assertIn(
            "after a board reboot",
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
                # mkdir, then the device-group check, then the install script.
                side_effect=[
                    "",
                    "xilinx video render",
                    RuntimeError("install script failed on remote host"),
                ],
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
                    "overlay_id": "snn_overlay_v2",
                    "overlay_version": "2.0.0",
                    "target_part": "xc7z020clg400-1",
                    "supported_neuron_models": ["LIF"],
                    "supported_weight_bit_widths": [8],
                    "max_neurons": 4096,
                    "max_neurons_per_layer": 1024,
                    "max_synapses": 262144,
                    "max_populations": 4,
                    "max_layers": 4,
                    "dma_ip_name": "axi_dma_0",
                    "snn_ip_name": "snn_engine_0",
                    "register_map": {
                        "resolved_from_hwh": True,
                        "base_address": 1073741824,
                        "control_reg_offset": 0,
                        "global_interrupt_enable_offset": 4,
                        "interrupt_enable_offset": 8,
                        "interrupt_status_offset": 12,
                        "weights_ptr_offset": 16,
                        "layer_config_ptr_offset": 28,
                        "layer_count_offset": 40,
                        "weight_count_offset": 48,
                        "timestep_count_offset": 56,
                        "dma_channel": "axi_dma_0",
                        "timestep_us": 1000,
                    },
                    "weight_layout": {
                        "format": "int8_dense_row_major_ddr",
                        "storage": "dma_ddr",
                        "element_bytes": 1,
                        "max_entries": 262144,
                        "matrix_order": "post_by_pre",
                    },
                    "layer_config_layout": {
                        "format": "uint32_words",
                        "storage": "dma_ddr",
                        "words_per_layer": 8,
                        "max_layers": 4,
                        "fields": {
                            "input_size": 0,
                            "output_size": 1,
                            "weight_offset": 2,
                            "threshold": 3,
                            "leak_shift": 4,
                            "refractory": 5,
                        },
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
        manifest["weight_layout"]["storage"] = "mmio"
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

        status = self.state._inspect_local_pynq_overlay_package()

        self.assertFalse(status["ready"])
        self.assertFalse(status["manifestValid"])
        self.assertIn(
            "never connected to the engine",
            "\n".join(status["issues"]),
        )

    def test_overlay_failure_names_the_package_that_exists_not_the_missing_root(
        self,
    ) -> None:
        """In the container the module root is not there; the artifact dir is.

        Reporting the module root's "directory not found" for an artifact package
        that exists but is malformed told users to update a backend that was
        already current, and hid the real defect (a manifest key dropped by the
        overlay build) behind a path the image never ships.
        """
        artifact_root = self.repo_root / "artifacts" / "neurochip"
        artifact_staging = artifact_root / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(artifact_staging)
        manifest_path = artifact_staging / "overlay_manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        del manifest["register_map"]["dma_channel"]
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

        with mock.patch.dict(
            "os.environ",
            {"NMTK_NEUROCHIP_ARTIFACT_DIR": str(artifact_root)},
        ):
            status = self.state._inspect_local_pynq_overlay_package()

        self.assertFalse(status["ready"])
        self.assertEqual(status["stagingDir"], str(artifact_staging.resolve()))
        self.assertIn("dma_channel", "\n".join(status["issues"]))

    def test_overlay_install_message_distinguishes_invalid_from_absent(self) -> None:
        """"Files are there but rejected" is not "files are missing"."""
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(staging_dir)
        manifest_path = staging_dir / "overlay_manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        del manifest["register_map"]["dma_channel"]
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

        with (
            mock.patch.object(self.state, "_run_ssh") as run_ssh,
            mock.patch.object(self.state, "_run_scp") as run_scp,
        ):
            result = self.state.install_pynq_overlay_assets(board["id"])

        message = result["board"]["lastPreflightMessage"]
        self.assertEqual(result["board"]["state"], "overlay_missing")
        self.assertIn("does not match the contract", message)
        self.assertNotIn("is missing or incomplete", message)
        self.assertIn("dma_channel", message)
        run_ssh.assert_not_called()
        run_scp.assert_not_called()

    def test_overlay_v1_is_refused_with_a_reason_a_user_can_act_on(self) -> None:
        """v1 could not compute, so a board still carrying it must not be used.

        Its weight port was never connected to anything in the block design, so
        every weight the engine read was zero and the board returned silence
        that the app displayed as a successful hardware run.
        """
        staging_dir = self.repo_root / "Neurochip" / "overlay_staging" / "pynq_z2"
        _stage_overlay_package(staging_dir)
        manifest_path = staging_dir / "overlay_manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["overlay_id"] = "snn_overlay_v1"
        manifest["overlay_version"] = "1.0.1"
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

        status = self.state._inspect_local_pynq_overlay_package()

        self.assertFalse(status["ready"])
        self.assertFalse(status["manifestValid"])
        issues = "\n".join(status["issues"])
        self.assertIn("always returns empty output", issues)
        self.assertIn("Install the overlay again", issues)
        # No terminal instructions: the app owns overlay installation.
        self.assertNotIn("ssh", issues.lower())
        self.assertNotIn("vivado", issues.lower())

    # ------------------------------------------------------------------
    # Privileged promotion
    #
    # A user-space runtime cannot program the PL at all: PYNQ's `Overlay(...)`
    # raises "Root permissions required." So provisioning has to end with a
    # privileged service whenever the board will give us root, or the board
    # reaches "ready" in the app and fails every deploy.
    # ------------------------------------------------------------------

    def _password_board(self) -> dict[str, Any]:
        return self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
                "authMode": "password",
                "password": "board-secret",
            }
        )

    def test_provisioning_promotes_a_user_space_install_to_a_root_service(self) -> None:
        board = self._password_board()
        # Read once after the install script, once after the promotion.
        statuses = [
            {"installMode": "user-space", "effectivePynqPython": "/usr/bin/python3"},
            {"installMode": "systemd", "effectivePynqPython": "/usr/bin/python3"},
        ]

        with (
            mock.patch.object(self.state, "_build_local_pynq_bundle"),
            mock.patch.object(self.state, "_run_ssh", return_value="") as run_ssh,
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(self.state, "_run_ssh_sudo", return_value="") as run_sudo,
            mock.patch.object(self.state, "_wait_for_board_agent_health"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                side_effect=statuses,
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                return_value={
                    "board": launcher_server._serialize_pynq_board(
                        self.state._get_pynq_board(board["id"])
                    )
                },
            ),
        ):
            result = self.state.provision_pynq_board(board["id"])

        sudo_commands = [call.args[1] for call in run_sudo.call_args_list]
        self.assertIn("true", sudo_commands)
        self.assertIn(
            "mv /tmp/neurochip-pynq-agent.service "
            "/etc/systemd/system/neurochip-pynq-agent.service",
            sudo_commands,
        )
        self.assertIn("systemctl daemon-reload", sudo_commands)
        self.assertIn("systemctl enable neurochip-pynq-agent.service", sudo_commands)
        self.assertIn("systemctl restart neurochip-pynq-agent.service", sudo_commands)
        # The user-space agent has to stop before the service claims its port.
        stop_index = next(
            index
            for index, call in enumerate(run_ssh.call_args_list)
            if "pkill" in call.args[1]
        )
        stage_index = next(
            index
            for index, call in enumerate(run_ssh.call_args_list)
            if "systemd/neurochip-pynq-agent.service" in call.args[1]
        )
        self.assertLess(stage_index, stop_index)
        self.assertEqual(result["installStatus"]["installMode"], "systemd")

    def test_promotion_is_skipped_without_a_password_and_leaves_the_agent_running(
        self,
    ) -> None:
        """No stored password means no root — but also no half-finished switch."""
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        def ssh(_board: Any, command: str) -> str:
            if command.startswith("sudo -n"):
                raise RuntimeError("sudo: a terminal is required to read the password")
            return ""

        with (
            mock.patch.object(self.state, "_run_ssh", side_effect=ssh) as run_ssh,
            mock.patch.object(self.state, "_run_ssh_sudo") as run_sudo,
        ):
            status = self.state._promote_pynq_install_to_systemd(
                self.state._get_pynq_board(board["id"]),
                "/tmp/bundle",
                {"installMode": "user-space"},
            )

        self.assertEqual(status["installMode"], "user-space")
        # No password, so the password helper is never reached.
        run_sudo.assert_not_called()
        self.assertFalse(
            [call for call in run_ssh.call_args_list if "pkill" in call.args[1]]
        )

    def test_promotion_leaves_the_user_space_agent_running_when_sudo_is_refused(
        self,
    ) -> None:
        board = self._password_board()

        with (
            mock.patch.object(self.state, "_run_ssh", return_value="") as run_ssh,
            mock.patch.object(
                self.state,
                "_run_ssh_sudo",
                side_effect=RuntimeError("sudo: a password is required"),
            ),
        ):
            status = self.state._promote_pynq_install_to_systemd(
                self.state._get_pynq_board(board["id"]),
                "/tmp/bundle",
                {"installMode": "user-space"},
            )

        self.assertEqual(status["installMode"], "user-space")
        # Sudo is probed before anything is torn down, so the working runtime
        # survives a board that will not give us root.
        self.assertFalse(
            [call for call in run_ssh.call_args_list if "pkill" in call.args[1]]
        )

    def test_a_failed_promotion_restores_the_user_space_runtime(self) -> None:
        board = self._password_board()

        def sudo(_board: Any, command: str, **_kwargs: Any) -> str:
            if command.startswith("systemctl enable"):
                raise RuntimeError("Failed to enable unit")
            return ""

        with (
            mock.patch.object(self.state, "_run_ssh", return_value=""),
            mock.patch.object(self.state, "_run_ssh_sudo", side_effect=sudo),
            mock.patch.object(
                self.state, "_restart_user_space_agent"
            ) as restart_user_space,
            mock.patch.object(self.state, "_wait_for_board_agent_health"),
        ):
            status = self.state._promote_pynq_install_to_systemd(
                self.state._get_pynq_board(board["id"]),
                "/tmp/bundle",
                {"installMode": "user-space"},
            )

        restart_user_space.assert_called_once()
        self.assertEqual(status["installMode"], "user-space")

    def test_promotion_rewrites_the_install_mode_the_board_reports(self) -> None:
        """Preflight and every restart path branch on this file, not on us."""
        board = self._password_board()

        with mock.patch.object(self.state, "_run_ssh", return_value="") as run_ssh:
            self.state._write_remote_pynq_install_mode(
                self.state._get_pynq_board(board["id"]),
                "systemd",
                "Runtime installed as a privileged systemd service.",
            )

        command = run_ssh.call_args.args[1]
        self.assertIn("python3 -c", command)
        self.assertIn("install-status.json", command)
        self.assertIn("systemd", command)

    def test_systemd_restart_uses_the_stored_password(self) -> None:
        """The stock PYNQ image has no passwordless sudo, so `sudo` alone hangs."""
        board = self._password_board()

        with (
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(self.state, "_run_ssh") as run_ssh,
            mock.patch.object(self.state, "_run_ssh_sudo", return_value="") as run_sudo,
            mock.patch.object(self.state, "_wait_for_board_agent_health"),
            mock.patch.object(
                self.state,
                "_refresh_pynq_board_preflight",
                return_value={"board": {"state": "ready"}},
            ),
        ):
            self.state.restart_pynq_runtime(board["id"])

        self.assertEqual(
            [call.args[1] for call in run_sudo.call_args_list],
            ["systemctl restart neurochip-pynq-agent.service"],
        )
        self.assertFalse(
            [call for call in run_ssh.call_args_list if "sudo" in call.args[1]]
        )
