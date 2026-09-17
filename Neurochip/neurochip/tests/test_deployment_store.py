from pathlib import Path

import pytest

from neurochip.app.schemas.deployments import DeploymentRecord
from neurochip.app.services.deployment_store import (
    DB_PATH,
    get_deployment,
    list_deployments,
    record_deployment,
)


@pytest.fixture(autouse=True)
def cleanup_db():
    # Remove DB before and after each test
    if Path(DB_PATH).exists():
        Path(DB_PATH).unlink()
    yield
    if Path(DB_PATH).exists():
        Path(DB_PATH).unlink()


def test_record_and_get_deployment():
    record = DeploymentRecord(
        id="test-1",
        timestamp="2026-03-19T10:00:00Z",
        network_spec_hash="hash123",
        target_id="teensy41",
        quantization_bits=8,
        firmware_version="v1.0",
        serial_port="/dev/ttyACM0",
        device_id="dev001",
        notes="Test deployment",
    )

    saved = record_deployment(record)
    assert saved.id == "test-1"

    retrieved = get_deployment("test-1")
    assert retrieved is not None
    assert retrieved.id == "test-1"
    assert retrieved.target_id == "teensy41"


def test_list_deployments():
    for i in range(3):
        record = DeploymentRecord(
            id=f"test-{i}",
            timestamp=f"2026-03-19T10:00:0{i}Z",
            network_spec_hash="hash",
            target_id="teensy41" if i < 2 else "loihi2",
            quantization_bits=8,
            firmware_version="v1.0",
            serial_port=None,
            device_id=None,
            notes=None,
        )
        record_deployment(record)

    all_deploys = list_deployments()
    assert len(all_deploys) == 3

    teensy_deploys = list_deployments(target_id="teensy41")
    assert len(teensy_deploys) == 2

    loihi_deploys = list_deployments(target_id="loihi2")
    assert len(loihi_deploys) == 1


def test_get_nonexistent_deployment():
    assert get_deployment("ghost") is None
