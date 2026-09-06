"""Launcher control service tests: Akida device diagnosis (board verdicts, kernel counters, simulator vs hardware)."""

import tempfile
from pathlib import Path

from base import LauncherControlServiceTestBase

from nmtk.launcher_control import (
    provisioning_helpers,
)


class TestLauncherAkidaDeviceDiagnosis(LauncherControlServiceTestBase):
    @staticmethod
    def _remote_control_namespace() -> dict[str, object]:
        """Load the remote-control service the installer actually ships.

        It lives as source text inside provisioning_helpers, so importing it is
        the only way to test the diagnosis it produces rather than a copy that
        may have drifted.
        """
        namespace: dict[str, object] = {"__name__": "akida_remote_control_under_test"}
        exec(  # noqa: S102 - the subject under test is generated source
            compile(
                provisioning_helpers._remote_control_script_text(),
                "akida_remote_control_service.py",
                "exec",
            ),
            namespace,
        )
        return namespace

    def _device_message(
        self,
        *,
        runtime_target: str,
        kernel_log: str = "",
        link_errors: int | None = None,
        probe: dict[str, object] | None = None,
    ) -> str:
        namespace = self._remote_control_namespace()
        namespace["_kernel_log_text"] = lambda: kernel_log
        namespace["_correctable_link_errors"] = lambda _probe: link_errors
        device_message = namespace["_akida_device_message"]
        return device_message(
            probe
            if probe is not None
            else {
                "present": True,
                "bdf": "0000:03:00.0",
                "driver": "akida-pcie",
                "memorySpaceEnabled": True,
            },
            "",
            runtime_target,
        )

    def test_board_that_passes_every_static_check_but_runs_the_simulator_is_named(
        self,
    ) -> None:
        """The case that reported nothing useful for a whole afternoon.

        Board fitted, driver bound, PCI memory space enabled -- so none of the
        existing checks fire -- yet the SDK falls back to the simulator because
        transfers to the card time out. It used to surface as "Optional Akida
        capability is degraded."
        """
        message = self._device_message(runtime_target="akd1000_simulator")
        self.assertIn("fitted and its driver is loaded", message)
        self.assertIn("stops responding", message)
        self.assertIn("fully off and on again", message)

        # A working card must never be told it is broken.
        self.assertEqual(self._device_message(runtime_target="hardware"), "")

    def test_unresponsive_board_only_blames_power_saving_when_the_kernel_said_so(
        self,
    ) -> None:
        aspm = self._device_message(
            runtime_target="akd1000_simulator",
            kernel_log="akida-pcie 0000:03:00.0: can't disable ASPM; OS doesn't have ASPM control",
        )
        self.assertIn("PCIe power management (ASPM)", aspm)
        self.assertIn("BIOS", aspm)

        timeouts = self._device_message(
            runtime_target="software_fallback",
            kernel_log="akida-pcie 0000:03:00.0: DMA wait completion timed out",
        )
        self.assertIn("transfers to the board time out", timeouts)
        self.assertNotIn("ASPM", timeouts)

        # No kernel log (the service user may not read it) and no error counter:
        # say what was observed and nothing more.
        bare = self._device_message(runtime_target="akd1000_simulator")
        self.assertNotIn("ASPM", bare)
        self.assertNotIn("time out", bare)

        counted = self._device_message(
            runtime_target="akd1000_simulator", link_errors=16
        )
        self.assertIn("logged 16 errors", counted)
        self.assertIn("reseating", counted)

    def test_existing_board_verdicts_still_win_over_the_simulator_case(self) -> None:
        wedged = self._device_message(
            runtime_target="akd1000_simulator",
            probe={
                "present": True,
                "bdf": "0000:03:00.0",
                "driver": "akida-pcie",
                "memorySpaceEnabled": False,
            },
        )
        self.assertIn("has stopped responding", wedged)

        absent = self._device_message(
            runtime_target="akd1000_simulator",
            probe={
                "present": False,
                "bdf": "",
                "driver": "",
                "memorySpaceEnabled": None,
            },
        )
        self.assertEqual(absent, "No Akida board was found in this host.")

        unbound = self._device_message(
            runtime_target="akd1000_simulator",
            probe={
                "present": True,
                "bdf": "0000:03:00.0",
                "driver": "",
                "memorySpaceEnabled": True,
            },
        )
        self.assertIn("PCIe driver is not loaded", unbound)

    def test_correctable_link_errors_reads_the_kernel_counter(self) -> None:
        namespace = self._remote_control_namespace()
        with tempfile.TemporaryDirectory() as raw:
            devices_root = Path(raw)
            device = devices_root / "0000:03:00.0"
            device.mkdir()
            (device / "aer_dev_correctable").write_text(
                "RxErr 14\nBadTLP 0\nBadDLLP 4\nTOTAL_ERR_COR 16\n", encoding="utf-8"
            )
            namespace["PCI_DEVICES_ROOT"] = devices_root
            read = namespace["_correctable_link_errors"]
            self.assertEqual(read({"bdf": "0000:03:00.0"}), 16)
            # Absent counter (older kernels) and no board must not raise.
            self.assertIsNone(read({"bdf": "0000:04:00.0"}))
            self.assertIsNone(read({"bdf": ""}))
