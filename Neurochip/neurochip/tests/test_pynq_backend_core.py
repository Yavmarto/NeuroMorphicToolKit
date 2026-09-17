"""Tests for `PYNQBackend` (state machine, mode selection) and `pynq_errors`.

All tests run without the ``pynq`` library — the backend falls back to
`PynqSimulator` automatically.
"""

from unittest.mock import patch

import pytest
from pynq_backend_fixtures import (
    ONE_TO_ONE_LAYER,
    ONE_TO_TWO_LAYER,
    FakeDma,
    FakeSnnIp,
    write_overlay_manifest,
)

from neurochip.app.services import pynq_backend as pynq_backend_module
from neurochip.app.services.pynq_backend import PYNQBackend
from neurochip.app.services.pynq_errors import (
    ConfigurationError,
    DmaTransferError,
    OverlayLoadError,
    PynqRuntimeError,
)
from neurochip.app.services.pynq_overlay_assets import DEFAULT_PYNQ_OVERLAY_DIR
from neurochip.app.services.pynq_simulator import PynqState


class TestPynqErrors:
    def test_base_error_has_code(self):
        err = PynqRuntimeError("boom")
        assert err.error_code == "PYNQ_RUNTIME_ERROR"
        assert str(err) == "boom"

    def test_subclass_default_code(self):
        err = OverlayLoadError("bad file")
        assert err.error_code == "OVERLAY_LOAD_FAILED"
        assert isinstance(err, PynqRuntimeError)

    def test_custom_code_override(self):
        err = DmaTransferError("timeout", error_code="DMA_TIMEOUT")
        assert err.error_code == "DMA_TIMEOUT"


class TestPYNQBackend:
    def test_backend_uses_simulator_when_pynq_unavailable(self):
        backend = PYNQBackend(bitstream_path="test.bit")
        assert backend._simulator is not None
        assert backend.runtime_mode == "simulator"

    def test_backend_uses_isolated_interpreter_when_configured(self, tmp_path):
        fake_python = tmp_path / "python"
        fake_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        fake_python.chmod(0o755)
        with (
            patch.dict("os.environ", {"NEUROCHIP_PYNQ_PYTHON": str(fake_python)}, clear=False),
            patch.object(pynq_backend_module, "_subprocess_runtime_available", return_value=True),
        ):
            backend = PYNQBackend(bitstream_path="snn_overlay.bit")
        assert backend._simulator is None
        assert backend.runtime_mode == "hardware"

    def test_probe_real_pynq_device_access_uses_bounded_worker_timeout(self, tmp_path):
        fake_python = tmp_path / "python"
        fake_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        fake_python.chmod(0o755)
        with (
            patch.dict("os.environ", {"NEUROCHIP_PYNQ_PYTHON": str(fake_python)}, clear=False),
            patch.object(pynq_backend_module, "_subprocess_runtime_available", return_value=True),
            patch.object(
                PYNQBackend,
                "_run_worker",
                side_effect=OverlayLoadError(
                    "PYNQ probe device timed out after 7s",
                    error_code="PYNQ_DEVICE_PROBE_TIMEOUT",
                ),
            ) as run_worker,
            pytest.raises(OverlayLoadError) as exc_info,
        ):
            pynq_backend_module.probe_real_pynq_device_access(timeout_seconds=7.0)

        assert exc_info.value.error_code == "PYNQ_DEVICE_PROBE_TIMEOUT"
        assert run_worker.call_args.kwargs["timeout"] == 7.0
        assert run_worker.call_args.args[0]["bitstream_path"] == str(
            DEFAULT_PYNQ_OVERLAY_DIR / "snn_overlay.bit"
        )

    def test_resolve_device_probe_timeout_respects_env_and_bounds(self):
        cases = {
            "": 20.0,
            "9": 9.0,
            "0": 1.0,
            "999": 120.0,
            "not-a-number": 20.0,
        }
        for raw, expected in cases.items():
            with patch.dict(
                "os.environ",
                {"NEUROCHIP_PYNQ_DEVICE_PROBE_TIMEOUT_SECONDS": raw},
                clear=False,
            ):
                assert pynq_backend_module._resolve_device_probe_timeout() == expected

    def test_backend_resolves_relative_bitstream_to_overlay_dir(self):
        backend = PYNQBackend(bitstream_path="snn_overlay.bit")
        assert backend.bitstream_path == str(DEFAULT_PYNQ_OVERLAY_DIR / "snn_overlay.bit")

    def test_overlay_asset_status_reports_missing_default_assets(self):
        backend = PYNQBackend(bitstream_path="snn_overlay.bit")
        status = backend.overlay_asset_status
        assert status.ready_for_hardware is False
        assert status.bitstream_path.endswith("/overlays/snn_overlay.bit")
        assert status.hwh_path.endswith("/overlays/snn_overlay.hwh")
        assert status.manifest_path.endswith("/overlays/overlay_manifest.json")
        assert status.manifest_exists is False
        assert status.issues

    def test_backend_load_overlay(self):
        backend = PYNQBackend(bitstream_path="overlay.bit")
        backend.load_overlay()
        assert backend.current_state == "loaded"

    def test_backend_full_cycle(self):
        backend = PYNQBackend(bitstream_path="snn.bit")
        backend.load_overlay()
        backend.configure(
            weights=[2.0, 0.5],
            config={},
            layers=[dict(ONE_TO_TWO_LAYER, threshold=1)],
        )
        assert backend.current_state == "configured"
        result = backend.run(input_spikes=[1, 0], timesteps=2)
        # One word per output neuron per timestep.
        assert len(result["output_spikes"]) == 4
        assert result["timesteps"] == 2

    def test_backend_reset(self):
        backend = PYNQBackend(bitstream_path="snn.bit")
        backend.load_overlay()
        backend.configure(weights=[1.0], config={}, layers=[ONE_TO_ONE_LAYER])
        backend.reset()
        assert backend.current_state == "loaded"

    def test_backend_run_without_configure_raises(self):
        backend = PYNQBackend(bitstream_path="snn.bit")
        backend.load_overlay()
        with pytest.raises(ConfigurationError):
            backend.run(input_spikes=[0])

    def test_backend_configure_with_register_map(self):
        backend = PYNQBackend(bitstream_path="snn.bit")
        backend.load_overlay()
        custom_map = {"weights_ptr_offset": 0x2_0000, "layer_count_offset": 0x200}
        backend.configure(
            weights=[1.0], config={}, register_map=custom_map, layers=[ONE_TO_ONE_LAYER]
        )
        assert backend.current_state == "configured"

    def test_backend_refuses_in_process_configure(self):
        """The engine reads weights from DDR buffers only the worker can own.

        Overlay-v1 pushed weights through an AXI-Lite window the block design
        never connected to the engine's weight port, so this path could only
        ever have produced silence.
        """
        backend = PYNQBackend(bitstream_path="snn.bit")
        backend._simulator = None
        backend._pynq_python = None
        backend.state = PynqState.LOADED
        backend.snn_ip = FakeSnnIp()

        with pytest.raises(ConfigurationError) as exc_info:
            backend.configure(weights=[-1.0, 2.0], config={}, layers=[ONE_TO_TWO_LAYER])

        assert exc_info.value.error_code == "PYNQ_WORKER_REQUIRED"

    def test_backend_refuses_in_process_run(self):
        backend = PYNQBackend(bitstream_path="snn.bit")
        backend._simulator = None
        backend._pynq_python = None
        backend.state = PynqState.CONFIGURED
        backend.dma = FakeDma()
        backend.snn_ip = FakeSnnIp()

        with pytest.raises(ConfigurationError) as exc_info:
            backend.run(input_spikes=[1, 0], timesteps=2)

        assert exc_info.value.error_code == "PYNQ_WORKER_REQUIRED"

    def test_backend_invalid_extension(self):
        backend = PYNQBackend(bitstream_path="overlay.bin")
        with pytest.raises(OverlayLoadError):
            backend.load_overlay()

    def test_backend_hardware_mode_fails_when_bitstream_missing(self):
        with patch("neurochip.app.services.pynq_backend.PYNQ_AVAILABLE", True):
            backend = PYNQBackend(bitstream_path="missing.bit")
            assert backend.runtime_mode == "hardware"
            with pytest.raises(OverlayLoadError) as exc_info:
                backend.load_overlay()
            assert exc_info.value.error_code == "OVERLAY_NOT_FOUND"

    def test_backend_hardware_mode_requires_hwh_sidecar(self, tmp_path):
        bitstream_path = tmp_path / "custom.bit"
        bitstream_path.write_bytes(b"stub")
        with patch("neurochip.app.services.pynq_backend.PYNQ_AVAILABLE", True):
            backend = PYNQBackend(bitstream_path=str(bitstream_path))
            with pytest.raises(OverlayLoadError) as exc_info:
                backend.load_overlay()
            assert exc_info.value.error_code == "HWH_NOT_FOUND"

    def test_backend_subprocess_run_replays_configured_state(self, tmp_path):
        bitstream_path = tmp_path / "custom.bit"
        hwh_path = tmp_path / "custom.hwh"
        manifest_path = tmp_path / "overlay_manifest.json"
        bitstream_path.write_bytes(b"stub")
        hwh_path.write_bytes(b"stub")
        write_overlay_manifest(manifest_path)
        fake_python = tmp_path / "python"
        fake_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        fake_python.chmod(0o755)

        def _worker_response(payload, **_kwargs):
            if payload["action"] == "deploy":
                return {"ok": True}
            return {
                "ok": True,
                "result": {
                    "output_spikes": [0],
                    "timesteps": payload["timesteps"],
                    "execution_time_us": 12.0,
                },
            }

        with (
            patch.dict("os.environ", {"NEUROCHIP_PYNQ_PYTHON": str(fake_python)}, clear=False),
            patch.object(pynq_backend_module, "_subprocess_runtime_available", return_value=True),
            patch.object(PYNQBackend, "_run_worker", side_effect=_worker_response) as run_worker,
        ):
            backend = PYNQBackend(bitstream_path=str(bitstream_path))
            backend.load_overlay()
            backend.configure(weights=[1.0], config={}, layers=[ONE_TO_ONE_LAYER])
            result = backend.run(input_spikes=[0], timesteps=3)

        assert result["timesteps"] == 3
        assert run_worker.call_count == 2
