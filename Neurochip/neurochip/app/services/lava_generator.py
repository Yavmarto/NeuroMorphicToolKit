"""Offline Lava artifact generator that does not require the Lava SDK."""

import hashlib
import io
import json
import zipfile
from datetime import datetime

from ..._compat import UTC
from ...contracts.deployment_contracts import DeploymentManifest, TargetDevice
from ..schemas.estimation import NetworkInput


def generate_lava_package(network: NetworkInput, bit_width: int = 8) -> bytes:
    """Generate a Lava simulation scaffold as a ZIP archive."""
    config = {
        "artifact_kind": "simulation_scaffold",
        "generated_at": datetime.now(UTC).isoformat(),
        "weight_bit_width": bit_width,
        "num_neurons": network.num_neurons,
        "num_synapses": network.num_synapses,
    }
    config_json = json.dumps(config, indent=2)
    script = (
        '"""Generated Lava simulation scaffold."""\n\n'
        "from lava.proc.lif.process import LIF\n\n"
        f"network = LIF(shape=({network.num_neurons},), vth=1)\n"
        "# Connect the generated populations and run configuration for your experiment here.\n"
    )
    readme = (
        "# Lava simulation scaffold\n\n"
        "This archive is generated without importing Lava, so it can be exported on any host. "
        "Run `script.py` in an environment with lava-nc installed to finish configuring the simulation.\n"
    )
    checksum = hashlib.sha256((script + config_json + readme).encode()).hexdigest()
    manifest = DeploymentManifest(
        target_device=TargetDevice.LAVA,
        core_count=1,
        firmware_version="1.0.0",
        checksum_sha256=checksum,
    )
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("lava_deploy/script.py", script)
        archive.writestr("lava_deploy/config.json", config_json)
        archive.writestr("lava_deploy/README.md", readme)
        archive.writestr("lava_deploy/manifest.json", manifest.model_dump_json(indent=2))
    return buffer.getvalue()
