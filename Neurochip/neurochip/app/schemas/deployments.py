from pydantic import BaseModel, ConfigDict

from neurochip.contracts.deployment_contracts import DeploymentManifest, TargetDevice


class DeploymentRecord(BaseModel):
    """Validated deployment record received from HTTP request bodies."""

    model_config = ConfigDict(strict=True)

    id: str
    timestamp: str
    network_spec_hash: str
    target_id: str
    quantization_bits: int
    firmware_version: str
    serial_port: str | None = None
    device_id: str | None = None
    notes: str | None = None


__all__ = ["DeploymentManifest", "DeploymentRecord", "TargetDevice"]
