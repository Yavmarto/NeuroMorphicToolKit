"""BrainScaleS configuration generator."""

import hashlib
import io
import json
import zipfile
from datetime import datetime

from ..._compat import UTC
from ...contracts.deployment_contracts import DeploymentManifest, TargetDevice
from ..schemas.estimation import NetworkInput


def generate_brainscales_package(
    network: NetworkInput,
    bit_width: int = 4,
    quantized_weights: list[float] | None = None,
) -> bytes:
    """Generate a portable configuration scaffold for BrainScaleS tooling."""
    config = {
        "artifact_kind": "configuration_scaffold",
        "generated_at": datetime.now(UTC).isoformat(),
        "target": "BrainScaleS",
        "weight_bit_width": bit_width,
        "network": network.model_dump(),
        "quantized_weights": quantized_weights or [],
    }
    config_json = json.dumps(config, indent=2)
    readme = (
        "# BrainScaleS configuration scaffold\n\n"
        "This archive describes the network for EBRAINS/BrainScaleS tooling; it is not a "
        "compiled hardware image. Import `config.json` into the target-specific workflow "
        "available on your EBRAINS environment.\n"
    )
    checksum = hashlib.sha256((config_json + readme).encode()).hexdigest()
    manifest = DeploymentManifest(
        target_device=TargetDevice.BRAINSCALES,
        core_count=1,
        firmware_version="2.0.0",
        checksum_sha256=checksum,
    )
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("brainscales_deploy/config.json", config_json)
        archive.writestr("brainscales_deploy/README.md", readme)
        archive.writestr("brainscales_deploy/manifest.json", manifest.model_dump_json(indent=2))
    return buffer.getvalue()
