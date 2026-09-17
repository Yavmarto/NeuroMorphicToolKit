"""SpiNNaker script and configuration generator."""

import hashlib
import io
import json
import zipfile
from datetime import datetime

from ..._compat import UTC
from ...contracts.deployment_contracts import DeploymentManifest, TargetDevice
from ..schemas.estimation import NetworkInput


def generate_spinnaker_package(
    network: NetworkInput,
    bit_width: int = 16,
    quantized_weights: list[float] | None = None,
) -> bytes:
    """Generate a portable PyNN scaffold for a SpiNNaker deployment."""
    timestamp = datetime.now(UTC).isoformat()
    populations = [
        {"name": str(pop["name"]), "size": int(pop["size"])} for pop in network.populations
    ]
    connections = [
        {
            "pre": str(connection["pre"]),
            "post": str(connection["post"]),
            "weight_count": int(connection["weight_count"]),
        }
        for connection in network.connections
    ]
    config = {
        "artifact_kind": "simulation_scaffold",
        "generated_at": timestamp,
        "weight_bit_width": bit_width,
        "populations": populations,
        "connections": connections,
        "quantized_weights": quantized_weights or [],
    }
    script = f"""\"\"\"Generated PyNN/SpiNNaker deployment scaffold.\"\"\"

import pyNN.spiNNaker as sim

CONFIG = {json.dumps(config, indent=2)}

sim.setup(timestep=1.0)
populations = {{entry['name']: sim.Population(entry['size'], sim.IF_curr_exp()) for entry in CONFIG['populations']}}
# Add projections from CONFIG['connections'] for your board topology.
sim.end()
"""
    config_json = json.dumps(config, indent=2)
    readme = (
        "# SpiNNaker deployment scaffold\n\n"
        "This archive contains a PyNN scaffold, not a compiled board image. "
        "Open `network.py` on a host with PyNN/SpiNNaker installed, add the board-specific "
        "projection configuration, then run it through your normal SpiNNaker workflow.\n"
    )
    checksum = hashlib.sha256((script + config_json + readme).encode()).hexdigest()
    manifest = DeploymentManifest(
        target_device=TargetDevice.SPINNAKER,
        core_count=1,
        firmware_version="2.0.0",
        checksum_sha256=checksum,
    )
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("spinnaker_deploy/network.py", script)
        archive.writestr("spinnaker_deploy/spinnaker.json", config_json)
        archive.writestr("spinnaker_deploy/README.md", readme)
        archive.writestr("spinnaker_deploy/manifest.json", manifest.model_dump_json(indent=2))
    return buffer.getvalue()
