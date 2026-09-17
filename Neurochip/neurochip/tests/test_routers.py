from fastapi.testclient import TestClient

from neurochip.app.limiter import limiter
from neurochip.app.main import app
from neurochip.app.routers import akida as akida_router
from neurochip.app.routers import speck as speck_router
from neurochip.app.services import akida_router_support
from neurochip.app.services.akida_errors import AkidaModelConstructionError

# Use a fixture or setup/teardown to handle limiter state if possible,
# but for now, we'll keep the global disable and ensure other tests re-enable it.
limiter.enabled = False
client = TestClient(app)


def setup_module(module):
    limiter.enabled = False


def teardown_module(module):
    limiter.enabled = True


def test_list_targets():
    response = client.get("/api/neurochip/targets")
    assert response.status_code == 200
    data = response.json()
    assert len(data) > 0
    # Should be a list of target objects
    assert "teensy41" in [t["id"] for t in data]


def test_get_target():
    response = client.get("/api/neurochip/targets/teensy41")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == "teensy41"
    assert "Teensy" in data["name"]


def get_mock_network():
    return {
        "num_neurons": 100,
        "num_synapses": 1000,
        "neuron_model": "LIF",
        "populations": [{"name": "pop1", "size": 100}],
        "connections": [{"pre": "pop1", "post": "pop1", "weight_count": 1000}],
        "weight_bit_width": 32,
        "network_depth": 10,
    }


def test_analyze():
    response = client.post("/api/neurochip/analyze?target_id=teensy41", json=get_mock_network())
    assert response.status_code == 200
    data = response.json()
    assert "neuron_fit" in data
    assert data["neuron_fit"] == "pass"


def test_quantize():
    response = client.post(
        "/api/neurochip/quantize?bit_width=8&target_device=Teensy 4.1", json=get_mock_network()
    )
    assert response.status_code == 200
    data = response.json()
    assert "bit_width" in data


def test_quantize_batch():
    response = client.post(
        "/api/neurochip/quantize/batch?target_device=Teensy 4.1", json=get_mock_network()
    )
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) > 0
    assert "bit_width" in data[0]


def test_faults():
    response = client.post("/api/neurochip/faults", json=get_mock_network())
    assert response.status_code == 200
    data = response.json()
    assert "fault_type" in data
    assert len(data["fault_rates"]) == len(data["accuracies"])


def test_deployments():
    # Setup - mock record
    record = {
        "id": "1",
        "timestamp": "2026-03-15T10:00:00Z",
        "network_spec_hash": "abc123hash",
        "target_id": "teensy41",
        "quantization_bits": 8,
        "firmware_version": "v1.0",
        "serial_port": "/dev/ttyACM0",
        "device_id": "device001",
        "notes": "Test deploy",
    }

    # POST
    response = client.post("/api/neurochip/deployments", json=record)
    assert response.status_code == 200
    assert response.json()["id"] == "1"

    # GET
    response = client.get("/api/neurochip/deployments")
    assert response.status_code == 200
    data = response.json()
    assert len(data) >= 1
    assert any(d["id"] == "1" for d in data)

    # GET with target_id filter
    response = client.get("/api/neurochip/deployments?target_id=teensy41")
    assert response.status_code == 200
    data = response.json()
    assert all(d["target_id"] == "teensy41" for d in data)


def test_estimate_power():
    response = client.post(
        "/api/neurochip/estimate/power?target_id=teensy41", json=get_mock_network()
    )
    assert response.status_code == 200
    assert "total_energy_pj" in response.json()


def test_estimate_latency():
    response = client.post(
        "/api/neurochip/estimate/latency?target_id=teensy41", json=get_mock_network()
    )
    assert response.status_code == 200
    assert "typical_us" in response.json()


def test_export_teensy():
    response = client.post("/api/neurochip/export/teensy?bit_width=8", json=get_mock_network())
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/zip"


def test_export_loihi():
    response = client.post("/api/neurochip/export/loihi", json=get_mock_network())
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/zip"


def test_serial_ports():
    response = client.get("/api/neurochip/serial/ports")
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_serial_flash():
    # Mock file upload
    import io

    file_content = b"fake zip content"
    file = ("test.zip", io.BytesIO(file_content), "application/zip")

    response = client.post(
        "/api/neurochip/serial/flash", files={"file": file}, data={"port": "/dev/ttyACM0"}
    )
    assert response.status_code == 200
    assert "job_id" in response.json()

    job_id = response.json()["job_id"]
    response = client.get(f"/api/neurochip/serial/flash/{job_id}")
    assert response.status_code == 200
    assert response.json()["job_id"] == job_id


def test_akida_status_reports_runtime_target(monkeypatch):
    class _FakeBackend:
        def get_sdk_status(self):
            return {
                "sdk_available": False,
                "sdk_status": "not_available",
                "sdk_issues": ["unsupported_os", "sdk_not_available"],
                "state": "mapped",
                "model_summary": {"n_populations": 2},
                "runtime_target": "software_fallback",
                "device_info": "AkidaSimulator",
                "sdk_issue_detail": "Akida Python SDK is not installed.",
                "environment_checks": {
                    "host_supported": False,
                    "python_supported": True,
                    "tensorflow_available": False,
                    "cnn2snn_available": False,
                    "akida_models_available": False,
                    "recommended_runtime": "simulator_only",
                },
            }

    monkeypatch.setattr(akida_router, "backend_instance", _FakeBackend())

    response = client.get("/api/neurochip/akida/status")

    assert response.status_code == 200
    data = response.json()
    assert data["sdk_status"] == "not_available"
    assert data["runtime_target"] == "software_fallback"
    assert data["device_info"] == "AkidaSimulator"
    assert data["environment_checks"]["host_supported"] is False
    assert data["environment_checks"]["recommended_runtime"] == "simulator_only"


def test_akida_verify_reports_mapping_failure(monkeypatch):
    class _FakeBackend:
        def get_sdk_status(self):
            return {
                "sdk_available": True,
                "sdk_status": "mapping_failed",
                "sdk_issues": ["device_mapping_failure"],
                "state": "constructed",
                "model_summary": {"n_populations": 2},
                "runtime_target": "unknown",
                "device_info": None,
                "sdk_issue_detail": "Failed to map model to Akida device.",
                "environment_checks": {
                    "host_supported": True,
                    "python_supported": True,
                    "tensorflow_available": True,
                    "cnn2snn_available": True,
                    "akida_models_available": True,
                    "recommended_runtime": "local_sdk",
                },
            }

    monkeypatch.setattr(akida_router, "backend_instance", _FakeBackend())

    response = client.post("/api/neurochip/akida/verify")

    assert response.status_code == 200
    data = response.json()
    assert data["sdk_status"] == "mapping_failed"
    assert data["sdk_issues"] == ["device_mapping_failure"]
    assert data["sdk_issue_detail"] == "Failed to map model to Akida device."
    assert data["environment_checks"]["recommended_runtime"] == "local_sdk"
    assert response.headers["deprecation"] == "true"
    assert response.headers["link"] == '</api/neurochip/akida/map>; rel="successor-version"'


def test_akida_status_reports_remote_runtime_guidance(monkeypatch):
    class _FakeBackend:
        def get_sdk_status(self):
            return {
                "sdk_available": False,
                "sdk_status": "not_available",
                "sdk_issues": ["unsupported_python", "sdk_not_available"],
                "state": "constructed",
                "model_summary": {"n_populations": 2},
                "runtime_target": "unknown",
                "device_info": None,
                "sdk_issue_detail": (
                    "Akida SDK installation requires Python 3.10 to 3.12. "
                    "This Neurochip backend is running Python 3.9.18; use a "
                    "Linux or Windows Neurochip host running Python 3.10-3.12 "
                    "for SDK verification."
                ),
                "environment_checks": {
                    "host_supported": True,
                    "python_supported": False,
                    "tensorflow_available": True,
                    "cnn2snn_available": True,
                    "akida_models_available": True,
                    "recommended_runtime": "remote_sdk",
                },
            }

    monkeypatch.setattr(akida_router, "backend_instance", _FakeBackend())

    response = client.get("/api/neurochip/akida/status")

    assert response.status_code == 200
    data = response.json()
    assert data["sdk_issue_detail"].endswith("SDK verification.")
    assert data["environment_checks"]["recommended_runtime"] == "remote_sdk"
    assert data["environment_checks"]["python_supported"] is False


def test_akida_verify_reports_remote_runtime_guidance(monkeypatch):
    class _FakeBackend:
        def get_sdk_status(self):
            return {
                "sdk_available": False,
                "sdk_status": "not_available",
                "sdk_issues": ["unsupported_python", "sdk_not_available"],
                "state": "constructed",
                "model_summary": {"n_populations": 2},
                "runtime_target": "unknown",
                "device_info": None,
                "sdk_issue_detail": (
                    "Akida SDK installation requires Python 3.10 to 3.12. "
                    "This Neurochip backend is running Python 3.9.18; use a "
                    "Linux or Windows Neurochip host running Python 3.10-3.12 "
                    "for SDK verification."
                ),
                "environment_checks": {
                    "host_supported": True,
                    "python_supported": False,
                    "tensorflow_available": True,
                    "cnn2snn_available": True,
                    "akida_models_available": True,
                    "recommended_runtime": "remote_sdk",
                },
            }

    monkeypatch.setattr(akida_router, "backend_instance", _FakeBackend())

    response = client.post("/api/neurochip/akida/verify")

    assert response.status_code == 200
    data = response.json()
    assert data["sdk_issue_detail"].endswith("SDK verification.")
    assert data["environment_checks"]["recommended_runtime"] == "remote_sdk"
    assert data["environment_checks"]["python_supported"] is False


def test_akida_map_returns_structured_status_for_model_construction_failure(
    monkeypatch,
):
    class _FakeBackend:
        def construct_model(self, _mapped_network, bit_width=4):
            raise AkidaModelConstructionError(
                "Akida SDK model construction failed: tuple index out of range"
            )

    monkeypatch.setattr(akida_router_support, "AkidaBackend", _FakeBackend)
    monkeypatch.setattr(akida_router, "backend_instance", None)

    response = client.post(
        "/api/neurochip/akida/map",
        json={
            "akida_version": "akida2",
            "populations": [{"id": "sensor", "size": 8}, {"id": "motor", "size": 4}],
            "connections": [{"source": "sensor", "target": "motor", "units": 4}],
            "network_summary": {"n_populations": 2, "n_connections": 1},
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["state"] == "failed"
    assert "model_construction_failure" in data["sdk_issues"]
    assert "tuple index out of range" in data["sdk_issue_detail"]


def test_akida_verify_remains_backward_compatible_for_mapping(monkeypatch):
    calls: list[str] = []

    class _FakeBackend:
        def construct_model(self, _mapped_network, bit_width=4):
            calls.append(f"construct:{bit_width}")

        def map_to_device(self):
            calls.append("map")

        def get_sdk_status(self):
            return {
                "sdk_available": True,
                "sdk_status": "deployable",
                "sdk_issues": [],
                "state": "mapped",
                "model_summary": {"n_populations": 1, "n_connections": 0},
                "runtime_target": "hardware",
                "device_info": "AKD2000 PCIe",
                "sdk_issue_detail": None,
                "environment_checks": {
                    "host_supported": True,
                    "python_supported": True,
                    "tensorflow_available": True,
                    "cnn2snn_available": True,
                    "akida_models_available": True,
                    "recommended_runtime": "local_sdk",
                },
            }

    monkeypatch.setattr(akida_router_support, "AkidaBackend", _FakeBackend)
    monkeypatch.setattr(akida_router, "backend_instance", None)

    response = client.post(
        "/api/neurochip/akida/verify",
        json={
            "akida_version": "akida2",
            "populations": [{"id": "sensor", "size": 8}],
            "connections": [],
            "network_summary": {"n_populations": 1, "n_connections": 0},
        },
    )

    assert response.status_code == 200
    assert calls == ["construct:4", "map"]
    assert response.headers["deprecation"] == "true"
    assert response.headers["link"] == '</api/neurochip/akida/map>; rel="successor-version"'


def test_akida_map_constructs_and_maps_backend(monkeypatch):
    calls: list[str] = []

    class _FakeBackend:
        def construct_model(self, _mapped_network, bit_width=4):
            calls.append(f"construct:{bit_width}")

        def map_to_device(self):
            calls.append("map")

        def get_sdk_status(self):
            return {
                "sdk_available": True,
                "sdk_status": "deployable",
                "sdk_issues": [],
                "state": "mapped",
                "model_summary": {"n_populations": 2, "n_connections": 1},
                "runtime_target": "hardware",
                "device_info": "AKD2000 PCIe",
                "sdk_issue_detail": None,
                "environment_checks": {
                    "host_supported": True,
                    "python_supported": True,
                    "tensorflow_available": True,
                    "cnn2snn_available": True,
                    "akida_models_available": True,
                    "recommended_runtime": "local_sdk",
                },
            }

    monkeypatch.setattr(akida_router_support, "AkidaBackend", _FakeBackend)
    monkeypatch.setattr(akida_router, "backend_instance", None)

    response = client.post(
        "/api/neurochip/akida/map?bit_width=2",
        json={
            "akida_version": "akida2",
            "populations": [{"id": "sensor", "size": 8}, {"id": "motor", "size": 4}],
            "connections": [{"source": "sensor", "target": "motor", "units": 4}],
            "network_summary": {"n_populations": 2, "n_connections": 1},
        },
    )

    assert response.status_code == 200
    assert calls == ["construct:2", "map"]
    data = response.json()
    assert data["state"] == "mapped"
    assert data["sdk_status"] == "deployable"
    assert data["runtime_target"] == "hardware"


def test_akida_deploy_mapped_scaffold_skips_sdk_construction(monkeypatch):
    calls: list[str] = []

    class _FakeBackend:
        def prepare_mapped_network(self, _mapped_network, *, bit_width=4):
            calls.append(f"prepare:{bit_width}")

        def construct_model(self, _mapped_network, bit_width=4):
            calls.append(f"construct:{bit_width}")
            raise AssertionError("construct_model should not run for scaffold deploy")

        def generate_package(self, bit_width=None):
            calls.append(f"package:{bit_width}")
            return b"PK\x03\x04"

        current_state = "constructed"
        _runtime_target = "unknown"

    monkeypatch.setattr(akida_router_support, "AkidaBackend", _FakeBackend)
    monkeypatch.setattr(akida_router, "backend_instance", None)

    response = client.post(
        "/api/neurochip/akida/deploy/mapped?bit_width=4&deployment_mode=scaffold",
        json={
            "akida_version": "akida2",
            "populations": [{"id": "sensor", "size": 8}, {"id": "motor", "size": 4}],
            "connections": [{"source": "sensor", "target": "motor", "units": 4}],
        },
    )

    assert response.status_code == 200
    assert response.content.startswith(b"PK")
    assert calls == ["prepare:4", "package:4"]


def test_speck_status_reports_runtime_target(monkeypatch):
    class _FakeBackend:
        def get_status(self):
            return {
                "sdk_available": False,
                "sdk_status": "not_available",
                "sdk_issues": ["samna_missing", "sdk_not_available"],
                "state": "mapped",
                "model_summary": {"n_populations": 2},
                "runtime_target": "software_fallback",
                "device_info": "SpeckSimulator",
                "sdk_issue_detail": "samna and sinabs are not both installed; Speck runtime is using the simulator.",
                "environment_checks": {
                    "host_supported": True,
                    "python_supported": True,
                    "sinabs_available": False,
                    "samna_available": False,
                    "device_discovery_supported": False,
                    "device_discovered": False,
                    "discovered_device_count": 0,
                    "recommended_runtime": "simulator",
                },
            }

    monkeypatch.setattr(speck_router, "backend", _FakeBackend())

    response = client.get("/api/neurochip/hardware/speck/status")

    assert response.status_code == 200
    data = response.json()
    assert data["runtime_target"] == "software_fallback"
    assert data["device_info"] == "SpeckSimulator"
    assert data["environment_checks"]["recommended_runtime"] == "simulator"


def test_speck_reset_returns_constructed_state(monkeypatch):
    class _FakeBackend:
        current_state = "constructed"

        def reset(self):
            return None

    monkeypatch.setattr(speck_router, "backend", _FakeBackend())

    response = client.post("/api/neurochip/hardware/speck/reset")

    assert response.status_code == 200
    assert response.json() == {"status": "reset", "state": "constructed"}
