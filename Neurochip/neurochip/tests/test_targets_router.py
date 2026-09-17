import json
from unittest.mock import mock_open, patch

from fastapi.testclient import TestClient

from neurochip.app.main import app

client = TestClient(app, raise_server_exceptions=False)

# A valid profile that satisfies HardwareProfile constraints
VALID_PROFILE = {
    "id": "teensy41",
    "name": "Teensy 4.1",
    "manufacturer": "PJRC",
    "description": "Powerful ARM Cortex-M7 microcontroller",
    "core_count": 1,
    "neuron_capacity": 4096,
    "supported_neuron_models": ["LIF"],
    "weight_bit_widths": [8, 16, 32],
    "on_chip_memory_kb": 1024,
    "io_pins": 55,
    "clock_speed_mhz": 600.0,
    "power_envelope_mw": 100.0,
    "pj_per_spike_op": 500.0,
    "access": "open",
    "notes": "some notes",
}


def test_get_target_not_found():
    response = client.get("/api/neurochip/targets/nonexistent_id")
    assert response.status_code == 404
    assert response.json()["detail"] == "Hardware target not found"


def test_get_target_malformed_json():
    # Patch exists to return True so it proceeds to read
    with patch("neurochip.app.routers.targets.Path.exists", return_value=True):
        # Patch open for a specific target to simulate malformed JSON
        with patch("builtins.open", mock_open(read_data="not a json")):
            response = client.get("/api/neurochip/targets/some_target")
            assert response.status_code == 500
            assert "Error reading profile" in response.json()["detail"]


def test_list_targets_skips_malformed_file(tmp_path):
    # Create a temporary targets directory
    targets_dir = tmp_path / "targets"
    targets_dir.mkdir()

    # Create one valid profile
    valid_file = targets_dir / "teensy41.json"
    with open(valid_file, "w") as f:
        json.dump(VALID_PROFILE, f)

    # Create one malformed profile (invalid JSON)
    malformed_file = targets_dir / "malformed.json"
    with open(malformed_file, "w") as f:
        f.write("not a json")

    # Create one profile that is valid JSON but fails schema validation
    invalid_schema_file = targets_dir / "invalid_schema.json"
    invalid_schema_profile = VALID_PROFILE.copy()
    invalid_schema_profile["core_count"] = 0  # Invalid: ge=1
    with open(invalid_schema_file, "w") as f:
        json.dump(invalid_schema_profile, f)

    # Patch _get_targets_dir to point to our temp directory
    with patch("neurochip.app.routers.targets._get_targets_dir", return_value=targets_dir):
        response = client.get("/api/neurochip/targets")
        assert response.status_code == 200
        profiles_resp = response.json()

        # Should only contain the one valid profile
        assert len(profiles_resp) == 1
        assert profiles_resp[0]["id"] == "teensy41"
