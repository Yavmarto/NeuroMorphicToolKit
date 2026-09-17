import io
import json
import zipfile

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from neurochip.app.main import app
from neurochip.contracts.deployment_contracts import DeploymentManifest, TargetDevice
from neurochip.contracts.pynq_runtime_artifact_contract import (
    PYNQ_OVERLAY_ID,
    PYNQ_OVERLAY_VERSION,
)

client = TestClient(app, raise_server_exceptions=False)


def get_mock_network():
    return {
        "num_neurons": 10,
        "num_synapses": 20,
        "neuron_model": "lif",
        "populations": [{"name": "in", "size": 10}, {"name": "out", "size": 10}],
        "connections": [{"pre": "in", "post": "out", "weight_count": 20}],
        "weight_bit_width": 8,
        "network_depth": 1,
    }


@pytest.mark.parametrize(
    "target, endpoint, manifest_path",
    [
        (TargetDevice.LAVA, "/api/neurochip/export/lava", "lava_deploy/manifest.json"),
        (TargetDevice.NEUROML, "/api/neurochip/export/neuroml", "neuroml_export/manifest.json"),
        (
            TargetDevice.TEENSY_41,
            "/api/neurochip/export/teensy",
            "neurochip_firmware/manifest.json",
        ),
        (TargetDevice.LOIHI_2, "/api/neurochip/export/loihi", "loihi_deploy/manifest.json"),
        (TargetDevice.AKIDA, "/api/neurochip/export/akida", "akida_deploy/manifest.json"),
        (
            TargetDevice.SPINNAKER,
            "/api/neurochip/export/spinnaker",
            "spinnaker_deploy/manifest.json",
        ),
        (
            TargetDevice.BRAINSCALES,
            "/api/neurochip/export/brainscales",
            "brainscales_deploy/manifest.json",
        ),
        (TargetDevice.PYNQ_Z2, "/api/neurochip/export/pynq", "pynq_deploy/manifest.json"),
    ],
)
def test_export_artifact_contract(target, endpoint, manifest_path):
    """
    Contract test for export artifacts.
    Ensures that the endpoint returns a valid ZIP file containing a manifest
    that complies with the DeploymentManifest contract.
    """
    payload = {"network": get_mock_network()}
    response = client.post(endpoint, json=payload)

    # 1. Basic response checks
    assert response.status_code == 200, f"Failed for {target}: {response.text}"
    assert response.headers["content-type"] == "application/zip"

    # 2. ZIP integrity and structure
    try:
        zip_data = io.BytesIO(response.content)
        with zipfile.ZipFile(zip_data) as zf:
            namelist = zf.namelist()
            assert manifest_path in namelist, f"Manifest missing in {target} artifact: {namelist}"

            # 3. Schema validation (Contract)
            manifest_content = zf.read(manifest_path).decode()
            try:
                manifest_json = json.loads(manifest_content)
                manifest = DeploymentManifest(**manifest_json)

                # Assert some basic manifest fields
                assert manifest.target_device == target
                assert len(manifest.checksum_sha256) == 64

            except json.JSONDecodeError as e:
                pytest.fail(
                    f"Serialization failure: {manifest_path} in {target} artifact is not valid JSON. Error: {e}"
                )
            except ValidationError as e:
                pytest.fail(
                    f"Schema mismatch: {manifest_path} in {target} artifact does not match DeploymentManifest contract. Errors: {e.json()}"
                )

    except zipfile.BadZipFile:
        pytest.fail(f"Integrity failure: {target} artifact is not a valid ZIP file")


def test_lava_artifact_integrity():
    """Specific integrity checks for Lava artifact."""
    response = client.post("/api/neurochip/export/lava", json={"network": get_mock_network()})
    zip_data = io.BytesIO(response.content)
    with zipfile.ZipFile(zip_data) as zf:
        # Check for expected files
        namelist = zf.namelist()
        assert "lava_deploy/script.py" in namelist
        assert "lava_deploy/README.md" in namelist

        # Basic content check
        script = zf.read("lava_deploy/script.py").decode()
        assert "from lava.proc.lif.process import LIF" in script
        assert "LIF(shape=(10,)" in script


def test_neuroml_artifact_integrity():
    """Specific integrity checks for NeuroML artifact."""
    response = client.post("/api/neurochip/export/neuroml", json={"network": get_mock_network()})
    zip_data = io.BytesIO(response.content)
    with zipfile.ZipFile(zip_data) as zf:
        # Check for expected files
        namelist = zf.namelist()
        assert "neuroml_export/network.nml" in namelist

        # Basic content check
        nml = zf.read("neuroml_export/network.nml").decode()
        assert '<?xml version="1.0" encoding="UTF-8"?>' in nml
        assert '<population id="pop" component="lif" size="10"/>' in nml


def test_pynq_artifact_integrity():
    """Specific integrity checks for PYNQ artifact."""
    response = client.post("/api/neurochip/export/pynq", json={"network": get_mock_network()})
    assert response.status_code == 200, f"PYNQ export failed: {response.text}"
    assert response.headers["content-type"] == "application/zip"

    zip_data = io.BytesIO(response.content)
    with zipfile.ZipFile(zip_data) as zf:
        namelist = zf.namelist()

        # Check all required files are present
        assert "pynq_deploy/overlay_config.json" in namelist
        assert "pynq_deploy/weights.bin" in namelist
        assert "pynq_deploy/register_map.json" in namelist
        assert "pynq_deploy/overlay_manifest.json" in namelist
        assert "pynq_deploy/manifest.json" in namelist
        assert "pynq_deploy/README.md" in namelist

        # Validate overlay_config.json structure
        overlay = json.loads(zf.read("pynq_deploy/overlay_config.json").decode())
        assert "network_name" in overlay
        assert "populations" in overlay
        assert "connections" in overlay
        assert "quantisation" in overlay
        assert overlay["overlay_id"] == PYNQ_OVERLAY_ID
        assert overlay["overlay_version"] == PYNQ_OVERLAY_VERSION
        assert len(overlay["populations"]) > 0
        assert overlay["quantisation"]["bits"] == 8

        # Validate register_map.json structure
        reg_map = json.loads(zf.read("pynq_deploy/register_map.json").decode())
        assert "base_address" in reg_map
        assert "control_reg_offset" in reg_map
        assert "dma_channel" in reg_map
        assert reg_map["dma_channel"] == "axi_dma_0"

        overlay_manifest = json.loads(zf.read("pynq_deploy/overlay_manifest.json").decode())
        assert overlay_manifest["overlay_id"] == PYNQ_OVERLAY_ID
        assert overlay_manifest["overlay_version"] == PYNQ_OVERLAY_VERSION
        assert overlay_manifest["supported_weight_bit_widths"] == [8]

        # Validate weights.bin is non-empty
        weights = zf.read("pynq_deploy/weights.bin")
        assert len(weights) > 0

        # Validate manifest
        manifest_json = json.loads(zf.read("pynq_deploy/manifest.json").decode())
        manifest = DeploymentManifest(**manifest_json)
        assert manifest.target_device == TargetDevice.PYNQ_Z2
        assert len(manifest.checksum_sha256) == 64


def test_export_accepts_network_that_fits_the_overlay_v2_contract():
    network = {
        "num_neurons": 256,
        "num_synapses": 1,
        "neuron_model": "LIF",
        "populations": [{"name": "in", "size": 128}, {"name": "out", "size": 128}],
        "connections": [{"pre": "in", "post": "out", "weight_count": 16384}],
        "weight_bit_width": 8,
        "network_depth": 1,
    }

    response = client.post("/api/neurochip/export/pynq", json={"network": network})

    assert response.status_code == 200, response.text
