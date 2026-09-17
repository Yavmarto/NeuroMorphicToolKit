from types import SimpleNamespace

import pytest

from neurochip.app.services import akida_backend
from neurochip.app.services.akida_simulator import AkidaSimulator, AkidaState


def test_collect_akida_environment_checks_marks_macos_as_simulator_only(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(akida_backend, "_current_platform_key", lambda: "macos")
    monkeypatch.setattr(akida_backend, "_current_python_version_tuple", lambda: (3, 11, 8))
    monkeypatch.setattr(akida_backend, "_module_available", lambda _name: False)

    checks = akida_backend.collect_akida_environment_checks()

    assert checks["host_supported"] is False
    assert checks["python_supported"] is True
    assert checks["recommended_runtime"] == "simulator_only"


def test_collect_akida_environment_checks_marks_unsupported_python_for_remote_sdk(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(akida_backend, "_current_platform_key", lambda: "linux")
    monkeypatch.setattr(akida_backend, "_current_python_version_tuple", lambda: (3, 9, 18))
    monkeypatch.setattr(akida_backend, "_module_available", lambda _name: False)

    checks = akida_backend.collect_akida_environment_checks()

    assert checks["host_supported"] is True
    assert checks["python_supported"] is False
    assert checks["recommended_runtime"] == "remote_sdk"


def test_get_sdk_status_reports_missing_metatf_tooling(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(akida_backend, "_current_platform_key", lambda: "linux")
    monkeypatch.setattr(akida_backend, "_current_python_version_tuple", lambda: (3, 11, 8))
    monkeypatch.setattr(
        akida_backend,
        "_module_available",
        lambda name: name == "tensorflow",
    )
    monkeypatch.setattr(akida_backend, "AKIDA_AVAILABLE", False)

    backend = akida_backend.AkidaBackend()
    status = backend.get_sdk_status()

    assert status["sdk_status"] == "not_available"
    assert "cnn2snn_missing" in status["sdk_issues"]
    assert "akida_models_missing" in status["sdk_issues"]
    assert "sdk_not_available" in status["sdk_issues"]
    assert status["environment_checks"]["tensorflow_available"] is True
    assert status["environment_checks"]["cnn2snn_available"] is False


def test_build_runtime_status_probes_hardware_without_mapped_model(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _FakeDevice:
        def __str__(self) -> str:
            return "AKD2000 PCIe"

    fake_akida = SimpleNamespace(
        devices=lambda: [_FakeDevice()],
        AKD1000=lambda: None,
    )

    monkeypatch.setattr(akida_backend, "AKIDA_AVAILABLE", True)
    monkeypatch.setattr(akida_backend, "akida", fake_akida)
    monkeypatch.setattr(akida_backend, "_current_platform_key", lambda: "linux")
    monkeypatch.setattr(akida_backend, "_current_python_version_tuple", lambda: (3, 11, 8))
    monkeypatch.setattr(akida_backend, "_module_available", lambda _name: True)

    status = akida_backend.build_akida_runtime_status(state="not_initialised")

    assert status["state"] == "not_initialised"
    assert status["sdk_status"] == "unknown"
    assert status["runtime_target"] == "hardware"
    assert status["device_info"] == "AKD2000 PCIe"
    assert status["sdk_issues"] == []


def test_build_runtime_status_without_model_keeps_environment_issue_codes(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(akida_backend, "AKIDA_AVAILABLE", False)
    monkeypatch.setattr(akida_backend, "_current_platform_key", lambda: "macos")
    monkeypatch.setattr(akida_backend, "_current_python_version_tuple", lambda: (3, 9, 18))
    monkeypatch.setattr(akida_backend, "_module_available", lambda _name: False)

    status = akida_backend.build_akida_runtime_status(state="not_initialised")

    assert status["sdk_status"] == "not_available"
    assert status["runtime_target"] == "software_fallback"
    assert status["device_info"] == "AkidaSimulator"
    assert "unsupported_os" in status["sdk_issues"]
    assert "unsupported_python" in status["sdk_issues"]
    assert "tensorflow_missing" in status["sdk_issues"]
    assert "cnn2snn_missing" in status["sdk_issues"]
    assert "akida_models_missing" in status["sdk_issues"]
    assert "sdk_not_available" in status["sdk_issues"]


def test_map_to_device_uses_akd1000_fallback_when_no_hardware_available(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _FakeModel:
        def map(self, _device: object) -> None:
            return None

    class _FakeAkd1000:
        pass

    fake_akida = SimpleNamespace(
        devices=lambda: [],
        AKD1000=lambda: _FakeAkd1000(),
    )

    monkeypatch.setattr(akida_backend, "AKIDA_AVAILABLE", True)
    monkeypatch.setattr(akida_backend, "akida", fake_akida)

    backend = akida_backend.AkidaBackend()
    backend._model = _FakeModel()
    backend.state = AkidaState.CONSTRUCTED

    backend.map_to_device()
    status = backend.get_sdk_status()

    assert backend.state == AkidaState.MAPPED
    assert status["runtime_target"] == "akd1000_simulator"
    assert status["sdk_status"] == "deployable"


def test_prepare_mapped_network_supports_scaffold_without_sdk_model() -> None:
    backend = akida_backend.AkidaBackend()

    backend.prepare_mapped_network(
        {
            "akida_version": "akida1",
            "populations": [
                {"id": "sensor", "size": 8, "role": "sensory"},
                {"id": "motor", "size": 4, "role": "motor"},
            ],
            "connections": [{"source": "sensor", "target": "motor", "units": 4, "weight": 1.0}],
            "network_summary": {"n_populations": 2, "n_connections": 1},
        },
        bit_width=2,
    )

    package_bytes = backend.generate_package()

    assert backend.current_state == "constructed"
    assert backend._model is None
    assert package_bytes.startswith(b"PK")


def test_construct_model_uses_akida_3d_input_shape(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured_input: dict[str, object] = {}
    captured_layers: list[object] = []

    class _FakeModel:
        def add(self, layer: object) -> None:
            captured_layers.append(layer)

    class _FakeInputData:
        def __init__(
            self,
            *,
            input_shape: tuple[int, int, int],
            input_bits: int,
            name: str,
        ) -> None:
            captured_input["input_shape"] = input_shape
            captured_input["input_bits"] = input_bits
            captured_input["name"] = name

    class _FakeFullyConnected:
        def __init__(self, *, name: str, units: int, weights_bits: int) -> None:
            self.name = name
            self.units = units
            self.weights_bits = weights_bits

    fake_akida = SimpleNamespace(
        Model=_FakeModel,
        InputData=_FakeInputData,
        FullyConnected=_FakeFullyConnected,
    )

    monkeypatch.setattr(akida_backend, "AKIDA_AVAILABLE", True)
    monkeypatch.setattr(akida_backend, "akida", fake_akida)

    backend = akida_backend.AkidaBackend()
    backend.construct_model(
        {
            "akida_version": "akida2",
            "populations": [
                {"id": "sensor", "size": 8, "role": "sensory"},
                {"id": "motor", "size": 4, "role": "motor"},
            ],
            "connections": [{"source": "sensor", "target": "motor", "units": 4, "weight": 1.0}],
        },
        bit_width=2,
    )

    assert captured_input == {
        "input_shape": (1, 1, 8),
        "input_bits": 2,
        "name": "sensor",
    }
    assert len(captured_layers) == 2


def test_construct_model_applies_mapped_lif_threshold_to_target_layer(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured_thresholds: dict[str, object] = {}

    class _FakeModel:
        def add(self, layer: object) -> None:
            pass

    class _FakeInputData:
        def __init__(
            self, *, input_shape: tuple[int, int, int], input_bits: int, name: str
        ) -> None:
            pass

    class _FakeFullyConnected:
        def __init__(self, *, name: str, units: int, weights_bits: int) -> None:
            self.name = name
            self.units = units

        def set_variable(self, name: str, values: object) -> None:
            captured_thresholds[name] = values

    fake_akida = SimpleNamespace(
        Model=_FakeModel,
        InputData=_FakeInputData,
        FullyConnected=_FakeFullyConnected,
    )

    monkeypatch.setattr(akida_backend, "AKIDA_AVAILABLE", True)
    monkeypatch.setattr(akida_backend, "akida", fake_akida)

    backend = akida_backend.AkidaBackend()
    backend.construct_model(
        {
            "akida_version": "akida2",
            "populations": [
                {"id": "sensor", "size": 8, "role": "sensory"},
                {
                    "id": "motor",
                    "size": 4,
                    "role": "motor",
                    "attributes": {"lif_threshold": 0.75},
                },
            ],
            "connections": [{"source": "sensor", "target": "motor", "units": 4, "weight": 1.0}],
        },
        bit_width=2,
    )

    assert captured_thresholds == {"threshold": [0.75, 0.75, 0.75, 0.75]}


def test_construct_model_degrades_gracefully_when_sdk_lacks_threshold_support(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _FakeModel:
        def add(self, layer: object) -> None:
            pass

    class _FakeInputData:
        def __init__(
            self, *, input_shape: tuple[int, int, int], input_bits: int, name: str
        ) -> None:
            pass

    class _FakeFullyConnected:
        def __init__(self, *, name: str, units: int, weights_bits: int) -> None:
            self.name = name
            self.units = units

    fake_akida = SimpleNamespace(
        Model=_FakeModel,
        InputData=_FakeInputData,
        FullyConnected=_FakeFullyConnected,
    )

    monkeypatch.setattr(akida_backend, "AKIDA_AVAILABLE", True)
    monkeypatch.setattr(akida_backend, "akida", fake_akida)

    backend = akida_backend.AkidaBackend()
    # _FakeFullyConnected exposes no set_variable — mirrors an installed SDK
    # version that doesn't support threshold configuration. Must not raise.
    backend.construct_model(
        {
            "akida_version": "akida2",
            "populations": [
                {"id": "sensor", "size": 8, "role": "sensory"},
                {
                    "id": "motor",
                    "size": 4,
                    "role": "motor",
                    "attributes": {"lif_threshold": 0.75},
                },
            ],
            "connections": [{"source": "sensor", "target": "motor", "units": 4, "weight": 1.0}],
        },
        bit_width=2,
    )

    assert backend.current_state == "constructed"


def test_simulator_honours_mapped_lif_threshold_per_population() -> None:
    mapped_network = {
        "akida_version": "akida1",
        "populations": [
            {"id": "sensor", "size": 2, "role": "sensory"},
            {
                "id": "motor",
                "size": 1,
                "role": "motor",
                "attributes": {"lif_threshold": 100.0},
            },
        ],
        "connections": [{"source": "sensor", "target": "motor", "units": 1, "weight": 1.0}],
    }

    simulator = AkidaSimulator()
    simulator.construct_model(mapped_network)
    simulator.map_to_device()

    result = simulator.run_inference([1.0, 1.0])

    # Weighted sum (2.0) clears the simulator's default threshold (1.0) but
    # not the mapped population's much higher lif_threshold (100.0).
    assert result["outputs"] == [0.0]


def test_sdk_input_normalisation_matches_first_population_size() -> None:
    assert akida_backend._normalise_vector_inputs([1.0], 3) == [1.0, 0.0, 0.0]
    assert akida_backend._normalise_vector_inputs([1.0, 2.0, 3.0, 4.0], 2) == [
        1.0,
        2.0,
    ]
