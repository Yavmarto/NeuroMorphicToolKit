import io
import json
import sys
import zipfile
from types import SimpleNamespace

import pytest

from neurochip.app.services import speck_backend
from neurochip.app.services.speck_errors import (
    SpeckConfigurationError,
    SpeckDeviceMappingError,
    SpeckInferenceError,
)


def _mapped_network() -> dict[str, object]:
    return {
        "populations": [
            {"id": "sensor", "size": 4, "neuron_model": "lif"},
            {"id": "motor", "size": 2, "neuron_model": "lif"},
        ],
        "connections": [{"source": "sensor", "target": "motor", "weight": 1.0}],
        "network_summary": {"n_populations": 2, "n_connections": 1, "weight_bit_width": 8},
    }


def _branching_mapped_network() -> dict[str, object]:
    return {
        "populations": [
            {"id": "sensor", "size": 4, "neuron_model": "lif"},
            {"id": "hidden_a", "size": 2, "neuron_model": "lif"},
            {"id": "hidden_b", "size": 2, "neuron_model": "lif"},
        ],
        "connections": [
            {"source": "sensor", "target": "hidden_a", "weight": 1.0},
            {"source": "sensor", "target": "hidden_b", "weight": 1.0},
        ],
        "network_summary": {"n_populations": 3, "n_connections": 2, "weight_bit_width": 8},
    }


def test_collect_speck_environment_checks_marks_missing_sdk_as_simulator(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(speck_backend, "SAMNA_AVAILABLE", False)
    monkeypatch.setattr(speck_backend, "SINABS_AVAILABLE", False)
    monkeypatch.setattr(sys, "platform", "linux")
    monkeypatch.setattr(sys, "version_info", (3, 11, 8))

    checks = speck_backend.collect_speck_environment_checks()

    assert checks["host_supported"] is True
    assert checks["python_supported"] is True
    assert checks["device_discovery_supported"] is False
    assert checks["device_discovered"] is False
    assert checks["recommended_runtime"] == "simulator"


def test_collect_speck_environment_checks_marks_discovered_speck_for_local_hw(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _DeviceInfo:
        device_type_name = "Speck2fDevKit"
        serial_number = "abc123"
        usb_bus_number = 1
        usb_device_address = 7

    monkeypatch.setattr(speck_backend, "SAMNA_AVAILABLE", True)
    monkeypatch.setattr(speck_backend, "SINABS_AVAILABLE", True)
    monkeypatch.setattr(sys, "platform", "linux")
    monkeypatch.setattr(sys, "version_info", (3, 11, 8))
    monkeypatch.setattr(speck_backend, "_list_samna_devices", lambda: [_DeviceInfo()])

    checks = speck_backend.collect_speck_environment_checks()

    assert checks["device_discovery_supported"] is True
    assert checks["device_discovered"] is True
    assert checks["discovered_device_count"] == 1
    assert checks["recommended_runtime"] == "local_hw"


def test_speck_backend_reports_model_summary_and_supports_reset() -> None:
    backend = speck_backend.SpeckBackend()
    backend.construct_model(_mapped_network())
    backend.map_to_device()

    status = backend.get_status()
    assert status["state"] == "mapped"
    assert status["runtime_target"] == "software_fallback"
    assert status["model_summary"] == {
        "n_populations": 2,
        "n_connections": 1,
        "weight_bit_width": 8,
    }

    backend.reset()

    assert backend.current_state == "constructed"


def test_speck_backend_generates_speck_artifact_package() -> None:
    backend = speck_backend.SpeckBackend()
    backend.construct_model(_mapped_network())

    artifact = backend.generate_package()

    with zipfile.ZipFile(io.BytesIO(artifact)) as zf:
        namelist = zf.namelist()
        assert "speck_deploy/model.json" in namelist
        assert "speck_deploy/compile_plan.json" in namelist
        assert "speck_deploy/config.samna" in namelist
        assert "speck_deploy/manifest.json" in namelist
        assert "speck_deploy/README.md" in namelist

        model_json = json.loads(zf.read("speck_deploy/model.json").decode("utf-8"))
        assert model_json["mapped_network"]["network_summary"]["weight_bit_width"] == 8

        compile_plan = json.loads(zf.read("speck_deploy/compile_plan.json").decode("utf-8"))
        assert compile_plan["compiler_backend"] == "normalized_sequential"
        assert compile_plan["deployable"] is True

        config_json = json.loads(zf.read("speck_deploy/config.samna").decode("utf-8"))
        assert config_json["device_type_name"] == "Speck2fDevKit"
        assert (
            config_json["samna_configuration_type"]
            == "samna.speck2f.configuration.SpeckConfiguration"
        )
        assert config_json["monitor_enable"] is True
        assert config_json["input_spike_layer"] == 12
        assert config_json["output_event_mode"] == "readout_pin"

        manifest_json = json.loads(zf.read("speck_deploy/manifest.json").decode("utf-8"))
        assert manifest_json["target_device"] == "SynSense Speck 2"
        assert manifest_json["artifact_schema_version"] == "1.0.0"


def test_speck_backend_status_reports_selected_hardware_runtime(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _DeviceInfo:
        device_type_name = "Speck2fDevKit"
        serial_number = "abc123"
        usb_bus_number = 1
        usb_device_address = 7

    monkeypatch.setattr(speck_backend, "SAMNA_AVAILABLE", True)
    monkeypatch.setattr(speck_backend, "SINABS_AVAILABLE", True)
    monkeypatch.setattr(sys, "platform", "linux")
    monkeypatch.setattr(sys, "version_info", (3, 11, 8))
    monkeypatch.setattr(speck_backend, "_list_samna_devices", lambda: [_DeviceInfo()])
    monkeypatch.setattr(speck_backend, "_discover_speck_devices", lambda: [_DeviceInfo()])

    backend = speck_backend.SpeckBackend()
    status = backend.get_status()

    assert status["runtime_target"] == "hardware"
    assert status["device_info"] == "Speck2fDevKit, serial=abc123, usb=1:7"
    assert status["environment_checks"]["device_discovered"] is True
    assert status["environment_checks"]["recommended_runtime"] == "local_hw"
    assert "Samna-backed hardware adapter" in status["sdk_issue_detail"]


def test_speck_backend_selects_hardware_runtime_when_device_is_discovered(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _DeviceInfo:
        device_type_name = "Speck2fDevKit"
        serial_number = "abc123"
        usb_bus_number = 1
        usb_device_address = 7

    monkeypatch.setattr(speck_backend, "SAMNA_AVAILABLE", True)
    monkeypatch.setattr(speck_backend, "SINABS_AVAILABLE", True)
    monkeypatch.setattr(sys, "platform", "linux")
    monkeypatch.setattr(sys, "version_info", (3, 11, 8))
    monkeypatch.setattr(speck_backend, "_list_samna_devices", lambda: [_DeviceInfo()])
    monkeypatch.setattr(speck_backend, "_discover_speck_devices", lambda: [_DeviceInfo()])

    backend = speck_backend.SpeckBackend()
    status = backend.get_status()

    assert backend._hardware_runtime is not None
    assert backend._simulator is None
    assert status["runtime_target"] == "hardware"
    assert status["device_info"] == "Speck2fDevKit, serial=abc123, usb=1:7"
    assert "Artifact-backed event I/O" in status["sdk_issue_detail"]


def test_speck_backend_hardware_runtime_opens_and_closes_device(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _DeviceInfo:
        device_type_name = "Speck2fDevKit"
        serial_number = "abc123"
        usb_bus_number = 1
        usb_device_address = 7

    opened: list[object] = []
    closed: list[object] = []
    applied_config_json: list[str] = []
    source_writes: list[list[object]] = []

    class _FakeReadoutPinValue:
        def __init__(self, index: int) -> None:
            self.index = index

    class _FakeSpeckConfiguration:
        def __init__(self) -> None:
            self._json = "{}"

        def from_json(self, raw: str) -> None:
            self._json = raw

    class _FakeModel:
        def apply_configuration(self, config: object) -> None:
            applied_config_json.append(getattr(config, "_json", ""))

        def get_sink_node(self) -> str:
            return "sink-node"

        def get_source_node(self) -> str:
            return "source-node"

    class _OpenedDevice:
        def get_model(self) -> _FakeModel:
            return _FakeModel()

    opened_device = _OpenedDevice()
    sink_events: list[list[object]] = [[], [_FakeReadoutPinValue(1), _FakeReadoutPinValue(1)]]

    class _FakeSink:
        def get_events(self) -> list[object]:
            return sink_events.pop(0) if sink_events else []

    class _FakeSource:
        def write(self, events: list[object]) -> None:
            source_writes.append(events)

    def _open_device(device_info: object) -> _OpenedDevice:
        opened.append(device_info)
        return opened_device

    fake_samna = SimpleNamespace(
        device=SimpleNamespace(
            open_device=_open_device,
            close_device=lambda device: closed.append(device),
        ),
        graph=SimpleNamespace(
            source_to=lambda _sink_node: _FakeSource(),
            sink_from=lambda _source_node: _FakeSink(),
        ),
        speck2f=SimpleNamespace(
            configuration=SimpleNamespace(SpeckConfiguration=_FakeSpeckConfiguration),
            event=SimpleNamespace(Spike=type("Spike", (), {})),
        ),
    )

    monkeypatch.setattr(speck_backend, "samna", fake_samna)
    monkeypatch.setattr(speck_backend, "SAMNA_AVAILABLE", True)
    monkeypatch.setattr(speck_backend, "SINABS_AVAILABLE", True)
    monkeypatch.setattr(sys, "platform", "linux")
    monkeypatch.setattr(sys, "version_info", (3, 11, 8))
    monkeypatch.setattr(speck_backend, "_list_samna_devices", lambda: [_DeviceInfo()])
    monkeypatch.setattr(speck_backend, "_discover_speck_devices", lambda: [_DeviceInfo()])

    backend = speck_backend.SpeckBackend()
    backend.construct_model(_mapped_network())
    backend.map_to_device()

    assert backend.current_state == "mapped"
    assert backend.get_status()["runtime_target"] == "hardware"
    assert len(opened) == 1
    assert backend._deployment_artifact is not None
    assert len(applied_config_json) == 1
    assert "monitor_enable" in applied_config_json[0]

    result = backend.run_inference([2.0, 0.0, 0.0, 0.0])

    assert len(source_writes) == 1
    assert len(source_writes[0]) == 2
    assert result["outputs"] == [0.0, 2.0]
    assert result["telemetry"]["event_types"]["_FakeReadoutPinValue"] == 2

    backend.reset()

    assert backend.current_state == "constructed"
    assert closed == [opened_device]


def test_speck_backend_hardware_runtime_inference_reports_not_implemented(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _DeviceInfo:
        device_type_name = "Speck2fDevKit"

    class _FakeSpeckConfiguration:
        def __init__(self) -> None:
            self._json = "{}"

        def from_json(self, raw: str) -> None:
            self._json = raw

    class _FakeModel:
        def apply_configuration(self, _config: object) -> None:
            return None

        def get_sink_node(self) -> str:
            return "sink-node"

        def get_source_node(self) -> str:
            return "source-node"

    class _OpenedDevice:
        def get_model(self) -> _FakeModel:
            return _FakeModel()

    class _FakeSource:
        def write(self, _events: list[object]) -> None:
            return None

    class _FakeSink:
        def get_events(self) -> list[object]:
            return []

    class _FakeSpike:
        def __init__(self) -> None:
            self.layer = 0
            self.feature = 0
            self.x = 0
            self.y = 0
            self.timestamp = 0

    fake_samna = SimpleNamespace(
        device=SimpleNamespace(
            open_device=lambda _device_info: _OpenedDevice(),
            close_device=lambda _device: None,
        ),
        graph=SimpleNamespace(
            source_to=lambda _sink_node: _FakeSource(),
            sink_from=lambda _source_node: _FakeSink(),
        ),
        speck2f=SimpleNamespace(
            configuration=SimpleNamespace(SpeckConfiguration=_FakeSpeckConfiguration),
            event=SimpleNamespace(Spike=_FakeSpike),
        ),
    )

    monkeypatch.setattr(speck_backend, "samna", fake_samna)
    monkeypatch.setattr(speck_backend, "SAMNA_AVAILABLE", True)
    monkeypatch.setattr(speck_backend, "SINABS_AVAILABLE", True)
    monkeypatch.setattr(sys, "platform", "linux")
    monkeypatch.setattr(sys, "version_info", (3, 11, 8))
    monkeypatch.setattr(speck_backend, "_list_samna_devices", lambda: [_DeviceInfo()])
    monkeypatch.setattr(speck_backend, "_discover_speck_devices", lambda: [_DeviceInfo()])

    backend = speck_backend.SpeckBackend()
    backend.construct_model(_mapped_network())
    backend.map_to_device()

    result = backend.run_inference([1.0, 0.0, 0.0, 1.0])

    assert result["outputs"] == [0.0, 0.0]
    assert result["telemetry"]["event_count"] == 0


def test_speck_backend_hardware_runtime_empty_spike_stream_raises(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _DeviceInfo:
        device_type_name = "Speck2fDevKit"

    class _FakeSpeckConfiguration:
        def __init__(self) -> None:
            self._json = "{}"

        def from_json(self, raw: str) -> None:
            self._json = raw

    class _FakeModel:
        def apply_configuration(self, _config: object) -> None:
            return None

        def get_sink_node(self) -> str:
            return "sink-node"

        def get_source_node(self) -> str:
            return "source-node"

    class _OpenedDevice:
        def get_model(self) -> _FakeModel:
            return _FakeModel()

    class _FakeSource:
        def write(self, _events: list[object]) -> None:
            return None

    class _FakeSink:
        def get_events(self) -> list[object]:
            return []

    class _FakeSpike:
        def __init__(self) -> None:
            self.layer = 0
            self.feature = 0
            self.x = 0
            self.y = 0
            self.timestamp = 0

    fake_samna = SimpleNamespace(
        device=SimpleNamespace(
            open_device=lambda _device_info: _OpenedDevice(),
            close_device=lambda _device: None,
        ),
        graph=SimpleNamespace(
            source_to=lambda _sink_node: _FakeSource(),
            sink_from=lambda _source_node: _FakeSink(),
        ),
        speck2f=SimpleNamespace(
            configuration=SimpleNamespace(SpeckConfiguration=_FakeSpeckConfiguration),
            event=SimpleNamespace(Spike=_FakeSpike),
        ),
    )

    monkeypatch.setattr(speck_backend, "samna", fake_samna)
    monkeypatch.setattr(speck_backend, "SAMNA_AVAILABLE", True)
    monkeypatch.setattr(speck_backend, "SINABS_AVAILABLE", True)
    monkeypatch.setattr(sys, "platform", "linux")
    monkeypatch.setattr(sys, "version_info", (3, 11, 8))
    monkeypatch.setattr(speck_backend, "_list_samna_devices", lambda: [_DeviceInfo()])
    monkeypatch.setattr(speck_backend, "_discover_speck_devices", lambda: [_DeviceInfo()])

    backend = speck_backend.SpeckBackend()
    backend.construct_model(_mapped_network())
    backend.map_to_device()

    with pytest.raises(SpeckInferenceError) as exc_info:
        backend.run_inference([0.0, 0.0, 0.0, 0.0])

    assert exc_info.value.error_code == "INFERENCE_EMPTY_SPIKE_STREAM"


def test_speck_backend_hardware_runtime_rejects_unsupported_compile_plan(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _DeviceInfo:
        device_type_name = "Speck2fDevKit"

    fake_samna = SimpleNamespace(
        device=SimpleNamespace(
            open_device=lambda _device_info: object(),
            close_device=lambda _device: None,
        ),
        speck2f=SimpleNamespace(
            configuration=SimpleNamespace(SpeckConfiguration=type("Cfg", (), {})),
        ),
    )

    monkeypatch.setattr(speck_backend, "samna", fake_samna)
    monkeypatch.setattr(speck_backend, "SAMNA_AVAILABLE", True)
    monkeypatch.setattr(speck_backend, "SINABS_AVAILABLE", True)
    monkeypatch.setattr(sys, "platform", "linux")
    monkeypatch.setattr(sys, "version_info", (3, 11, 8))
    monkeypatch.setattr(speck_backend, "_list_samna_devices", lambda: [_DeviceInfo()])
    monkeypatch.setattr(speck_backend, "_discover_speck_devices", lambda: [_DeviceInfo()])

    backend = speck_backend.SpeckBackend()
    backend.construct_model(_branching_mapped_network())

    with pytest.raises(SpeckDeviceMappingError) as exc_info:
        backend.map_to_device()

    assert exc_info.value.error_code == "UNSUPPORTED_COMPILE_PLAN"


def test_speck_backend_reset_before_construct_raises() -> None:
    backend = speck_backend.SpeckBackend()

    with pytest.raises(SpeckConfigurationError):
        backend.reset()
