"""Shared fakes, fixtures, and test data for the PYNQ backend test suite.

Not a `test_*.py` module itself -- imported by `test_pynq_backend_core.py`,
`test_pynq_backend_simulator.py`, `test_pynq_backend_worker.py`, and
`test_pynq_backend_router.py` so none of them has to redefine the fake PYNQ
collaborators or the FastAPI test client.
"""

import json
from typing import Any

from fastapi.testclient import TestClient

from neurochip.app.main import app
from neurochip.contracts.pynq_runtime_artifact_contract import DEFAULT_OVERLAY_MANIFEST

client = TestClient(app)


def write_overlay_manifest(path):
    path.write_text(json.dumps(DEFAULT_OVERLAY_MANIFEST, indent=2), encoding="utf-8")


class FakeSnnIp:
    def __init__(self) -> None:
        self.writes: list[tuple[int, int]] = []

    def write(self, offset: int, value: int) -> None:
        self.writes.append((offset, value))


class FakeBuffer(list[int]):
    physical_address = 0x1000_0000

    def freebuffer(self) -> None:
        return None

    def tolist(self) -> list[int]:
        return list(self)


class FakeNumpy:
    uint32 = int
    int8 = int

    @staticmethod
    def array(values: list[int], dtype: Any = None) -> list[int]:
        return list(values)

    @staticmethod
    def copyto(dest: list[int], src: list[int]) -> None:
        dest[:] = list(src)


class FakeDmaChannelWithoutTimeout:
    def __init__(self) -> None:
        self.transfers: list[list[int]] = []
        self.wait_calls = 0

    def transfer(self, buffer: list[int]) -> None:
        self.transfers.append(list(buffer))

    def wait(self) -> None:
        self.wait_calls += 1


class FakeDma:
    def __init__(self) -> None:
        self.sendchannel = FakeDmaChannelWithoutTimeout()
        self.recvchannel = FakeDmaChannelWithoutTimeout()


#: Minimal layer descriptors for the simulator, mirroring the fields the
#: overlay-v2 engine reads out of `layer_config`.
ONE_TO_ONE_LAYER = {
    "input_size": 1,
    "output_size": 1,
    "weight_offset": 0,
    "threshold": 1,
    "leak_shift": 0,
    "refractory": 0,
}
ONE_TO_TWO_LAYER = {
    "input_size": 1,
    "output_size": 2,
    "weight_offset": 0,
    "threshold": 1,
    "leak_shift": 0,
    "refractory": 0,
}


#: A register map as it looks once resolved from a built `.hwh`.
RESOLVED_REGISTER_MAP = {
    "resolved_from_hwh": True,
    "base_address": 0x4000_0000,
    "control_reg_offset": 0x00,
    "global_interrupt_enable_offset": 0x04,
    "interrupt_enable_offset": 0x08,
    "interrupt_status_offset": 0x0C,
    "weights_ptr_offset": 0x10,
    "layer_config_ptr_offset": 0x1C,
    "layer_count_offset": 0x28,
    "weight_count_offset": 0x30,
    "timestep_count_offset": 0x38,
    "dma_channel": "axi_dma_0",
    "timestep_us": 1000,
}
