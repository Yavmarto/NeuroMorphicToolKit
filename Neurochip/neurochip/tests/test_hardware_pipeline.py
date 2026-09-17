import io
import shutil
import subprocess
import time
import zipfile
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from neurochip.app.schemas.estimation import NetworkInput
from neurochip.app.services import (
    akida_backend,
    brainscales_generator,
    flash_service,
    loihi_generator,
    quantizer,
    spinnaker_generator,
    teensy_generator,
)


@pytest.fixture(scope="module")
def sample_network():
    return NetworkInput(
        num_neurons=10,
        num_synapses=20,
        neuron_model="LIF",
        populations=[{"name": "in", "size": 5}, {"name": "out", "size": 5}],
        connections=[{"pre": "in", "post": "out", "weight_count": 20}],
        weight_bit_width=8,
        network_depth=1,
    )


@pytest.fixture(scope="module")
def virtual_serial():
    # Setup virtual serial ports if they don't exist
    if not Path("/tmp/ttyV0").exists() or not Path("/tmp/ttyV1").exists():
        if not shutil.which("socat"):
            pytest.skip("socat not found and virtual serial ports not available")

        proc = subprocess.Popen(
            ["socat", "PTY,link=/tmp/ttyV0,raw,echo=0", "PTY,link=/tmp/ttyV1,raw,echo=0"]
        )
        time.sleep(1)
        yield "/tmp/ttyV0", "/tmp/ttyV1"
        proc.terminate()
    else:
        yield "/tmp/ttyV0", "/tmp/ttyV1"


@patch("neurochip.app.services.flash_service.subprocess.run")
def test_full_pipeline_teensy(mock_run, sample_network, virtual_serial):
    mock_run.return_value = MagicMock(returncode=0, stdout="", stderr="")
    v0, v1 = virtual_serial

    # 1. Quantization
    quant_res = quantizer.quantize(sample_network, bit_width=8, target_device="Teensy 4.1")
    assert quant_res.bit_width == 8

    # 2. Compilation (Export)
    zip_bytes = teensy_generator.generate_teensy_project(sample_network, bit_width=8)
    assert len(zip_bytes) > 0

    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        assert "neurochip_firmware/src/main.ino" in zf.namelist()
        assert "neurochip_firmware/platformio.ini" in zf.namelist()

    # 3. Flash (Simulated)
    # Start mock simulator on v1
    mock_proc = subprocess.Popen(["python3", "tests/mock_teensy.py", v1])
    time.sleep(1)

    try:
        job = flash_service.start_flash_job(zip_bytes, v0)

        # Poll for completion
        for _ in range(10):
            time.sleep(1)
            next_job = flash_service.get_flash_job(job.id)
            assert next_job is not None
            job = next_job
            if job.status in [flash_service.FlashStatus.DONE, flash_service.FlashStatus.FAILED]:
                break

        assert job.status == flash_service.FlashStatus.DONE
        assert job.error is None
    finally:
        mock_proc.terminate()


def test_loihi_export_format(sample_network):
    zip_bytes = loihi_generator.generate_loihi_package(sample_network, bit_width=8)
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        assert "loihi_deploy/deploy.py" in zf.namelist()
        assert "loihi_deploy/crossbar_weights.bin" in zf.namelist()


def test_akida_export_format(sample_network):
    zip_bytes = akida_backend.generate_akida_package(sample_network, bit_width=4)
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        assert "akida_deploy/model.json" in zf.namelist()
        assert "akida_deploy/weights.bin" in zf.namelist()


def test_brainscales_export_format(sample_network):
    zip_bytes = brainscales_generator.generate_brainscales_package(sample_network, bit_width=4)
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        assert "brainscales_deploy/config.json" in zf.namelist()


def test_spinnaker_export_format(sample_network):
    zip_bytes = spinnaker_generator.generate_spinnaker_package(sample_network, bit_width=16)
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        assert "spinnaker_deploy/network.py" in zf.namelist()
        assert "spinnaker_deploy/spinnaker.json" in zf.namelist()
