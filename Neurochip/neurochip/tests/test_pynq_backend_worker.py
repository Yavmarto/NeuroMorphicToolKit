"""Tests for `pynq_worker`: the subprocess-isolated hardware configure/load path.

All tests run without the ``pynq`` library.
"""

import importlib
import json
from typing import Any
from unittest.mock import patch

import pytest
from pynq_backend_fixtures import (
    ONE_TO_ONE_LAYER,
    ONE_TO_TWO_LAYER,
    RESOLVED_REGISTER_MAP,
    FakeBuffer,
    FakeDmaChannelWithoutTimeout,
    FakeNumpy,
    FakeSnnIp,
)

from neurochip.app.services.pynq_backend import PYNQBackend
from neurochip.app.services.pynq_errors import OverlayLoadError
from neurochip.app.services.pynq_worker import WorkerError, _configure_hardware
from neurochip.app.services.pynq_worker import _wait_for_dma_channel as worker_wait_for_dma_channel
from neurochip.contracts.pynq_runtime_artifact_contract import MAX_SYNAPSES


class TestPynqWorker:
    def test_worker_wait_handles_dma_wait_without_timeout_kwarg(self):
        channel = FakeDmaChannelWithoutTimeout()

        worker_wait_for_dma_channel(channel, timeout_s=0.01)

        assert channel.wait_calls == 1

    def test_worker_configure_hands_the_engine_buffer_addresses(self):
        fake_snn = FakeSnnIp()
        buffers: list[FakeBuffer] = []

        def _allocate(*, shape, dtype):
            buffer = FakeBuffer([0] * shape[0])
            buffer.physical_address = 0x1000_0000 + 0x1000 * len(buffers)
            buffers.append(buffer)
            return buffer

        with patch.object(importlib, "import_module", return_value=FakeNumpy):
            _configure_hardware(
                fake_snn,
                _allocate,
                weights=[-1.0, 2.0],
                layers=[ONE_TO_TWO_LAYER],
                register_map=RESOLVED_REGISTER_MAP,
                max_synapses=MAX_SYNAPSES,
            )

        writes = dict(fake_snn.writes)
        assert writes[RESOLVED_REGISTER_MAP["weights_ptr_offset"]] == buffers[0].physical_address
        assert (
            writes[RESOLVED_REGISTER_MAP["layer_config_ptr_offset"]] == buffers[1].physical_address
        )
        assert writes[RESOLVED_REGISTER_MAP["layer_count_offset"]] == 1
        assert writes[RESOLVED_REGISTER_MAP["weight_count_offset"]] == 2

    def test_worker_configure_refuses_an_unresolved_register_map(self):
        """Overlay-v1 defaulted every offset it could not find and wrote anyway."""
        with pytest.raises(WorkerError) as exc_info:
            _configure_hardware(
                FakeSnnIp(),
                lambda **_: FakeBuffer([0]),  # never reached
                weights=[1.0],
                layers=[ONE_TO_ONE_LAYER],
                register_map={},
                max_synapses=MAX_SYNAPSES,
            )

        assert exc_info.value.error_code == "OVERLAY_REGISTER_MAP_UNRESOLVED"

    def test_worker_configure_rejects_contract_synapse_overflow(self):
        with pytest.raises(WorkerError) as exc_info:
            _configure_hardware(
                None,
                None,
                weights=[1.0] * (MAX_SYNAPSES + 1),
                layers=[ONE_TO_ONE_LAYER],
                register_map=RESOLVED_REGISTER_MAP,
                max_synapses=MAX_SYNAPSES,
            )
        assert exc_info.value.error_code == "WEIGHT_BUFFER_OVERFLOW"


class TestPynqRootRequirement:
    """A runtime installed in user space passes every check and cannot deploy.

    PYNQ writes the bitstream through the FPGA manager, which only root may
    drive, and refuses with a bare "Root permissions required." that names
    neither the cause nor a way out. The user sees it at the end of a green
    board setup, so it has to say what to do.
    """

    def _fake_pynq(self, monkeypatch: Any, overlay_error: Exception) -> None:
        import sys
        import types

        module: Any = types.ModuleType("pynq")

        class _Device:
            devices = ["card0"]

        def _overlay(_path: str) -> Any:
            raise overlay_error

        module.Device = _Device
        module.Overlay = _overlay
        module.allocate = lambda *a, **k: None
        monkeypatch.setitem(sys.modules, "pynq", module)

    def test_worker_translates_pynqs_bare_root_message(self, tmp_path, monkeypatch):
        from neurochip.app.services.pynq_worker import _load_hardware

        bitstream = tmp_path / "snn_overlay.bit"
        bitstream.write_bytes(b"\x00")
        (tmp_path / "snn_overlay.hwh").write_text("<hwh/>", encoding="utf-8")
        self._fake_pynq(monkeypatch, RuntimeError("Root permissions required."))

        with pytest.raises(WorkerError) as raised:
            _load_hardware(str(bitstream), dma_ip_name="axi_dma_0", snn_ip_name="snn_engine_0")

        assert raised.value.error_code == "PYNQ_ROOT_REQUIRED"
        message = str(raised.value)
        assert "requires root" in message
        assert "Install the board runtime again from the app" in message
        # The app owns the fix; no terminal instructions.
        assert "sudo" not in message.lower()
        assert "ssh" not in message.lower()

    def test_other_overlay_failures_keep_their_own_code(self, tmp_path, monkeypatch):
        from neurochip.app.services.pynq_worker import _load_hardware

        bitstream = tmp_path / "snn_overlay.bit"
        bitstream.write_bytes(b"\x00")
        (tmp_path / "snn_overlay.hwh").write_text("<hwh/>", encoding="utf-8")
        self._fake_pynq(monkeypatch, RuntimeError("Timeout programming the PL"))

        with pytest.raises(WorkerError) as raised:
            _load_hardware(str(bitstream), dma_ip_name="axi_dma_0", snn_ip_name="snn_engine_0")

        assert raised.value.error_code == "OVERLAY_LOAD_FAILED"

    def test_worker_root_failure_reaches_the_backend_as_an_overlay_error(self):
        """Not a generic PynqRuntimeError: the code has to survive the hop."""
        backend = PYNQBackend.__new__(PYNQBackend)
        backend._pynq_python = "/usr/bin/python3"

        with patch("neurochip.app.services.pynq_backend.subprocess.run") as subprocess_run:
            subprocess_run.return_value = type(
                "R",
                (),
                {
                    "stdout": json.dumps(
                        {
                            "ok": False,
                            "detail": "requires root",
                            "error_code": "PYNQ_ROOT_REQUIRED",
                        }
                    ),
                    "stderr": "",
                },
            )()
            with pytest.raises(OverlayLoadError) as raised:
                backend._run_worker({"action": "load_overlay"})

        assert raised.value.error_code == "PYNQ_ROOT_REQUIRED"

    def test_deploy_reports_a_root_failure_as_a_fixable_setup_problem(self):
        """500 reads as "the board broke"; this is an install the app can redo."""
        from pynq_backend_fixtures import client

        with patch.object(
            PYNQBackend,
            "load_overlay",
            side_effect=OverlayLoadError(
                "The board runtime is not allowed to program the FPGA",
                error_code="PYNQ_ROOT_REQUIRED",
            ),
        ):
            response = client.post(
                "/hardware/pynq/deploy",
                json={"weights": [0.1], "config": {}},
                headers={"X-API-Key": "test_key"},
            )

        assert response.status_code == 422
        assert response.json()["detail"]["error_code"] == "PYNQ_ROOT_REQUIRED"
