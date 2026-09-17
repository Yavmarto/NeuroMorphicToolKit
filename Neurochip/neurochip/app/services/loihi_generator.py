"""Loihi 2 NxSDK deployment package generator."""

import hashlib
import io
import os
import struct
import zipfile
from collections.abc import Callable
from datetime import datetime
from typing import Any

from jinja2 import Environment, FileSystemLoader

from ..._compat import UTC
from ...contracts.deployment_contracts import DeploymentManifest, TargetDevice
from ..schemas.estimation import NetworkInput
from .cache_manager import cache_manager


def _get_template_dir() -> str:
    return os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..", "firmware_templates", "loihi"
    )


def _build_template_context(
    network: NetworkInput,
    bit_width: int = 8,
    board_id: str = "localhost",
    num_steps: int = 1000,
) -> dict[str, Any]:
    """Build context for Loihi template rendering."""
    populations = []
    connections = []

    for pop in network.populations:
        populations.append(
            {
                "name": pop["name"],
                "size": pop["size"],
                "threshold_mantissa": 100,
                "current_decay": 4096,
                "voltage_decay": 256,
                "refractory": 2,
            }
        )

    pop_sizes = {p["name"]: p["size"] for p in network.populations}

    for conn in network.connections:
        connections.append(
            {
                "pre": conn["pre"],
                "post": conn["post"],
                "pre_size": pop_sizes.get(conn["pre"], 1),
                "post_size": pop_sizes.get(conn["post"], 1),
            }
        )

    num_cores = max(1, network.num_neurons // 1024)

    return {
        "network_name": "SNN Network",
        "timestamp": datetime.now(UTC).isoformat(),
        "nxsdk_version": ">=1.0",
        "board_id": board_id,
        "partition_name": "neurochip_partition",
        "num_steps": num_steps,
        "num_cores": num_cores,
        "bit_width": bit_width,
        "populations": populations,
        "connections": connections,
    }


def _generate_mock_hdf5_bytes(network: NetworkInput, bit_width: int) -> bytes:
    """
    Generate a minimal binary file representing crossbar weights.

    In production, this would use h5py and neurodreamhand's crossbar_exporter.
    For now, generates a simple binary format with weight matrices.
    """
    buffer = io.BytesIO()

    # Simple binary format: for each connection, write pre_size, post_size, then weights
    pop_sizes = {p["name"]: p["size"] for p in network.populations}

    for conn in network.connections:
        pre_size = pop_sizes.get(conn["pre"], 1)
        post_size = pop_sizes.get(conn["post"], 1)
        buffer.write(struct.pack("II", pre_size, post_size))

        # Write zero weights (placeholder)
        num_weights = min(conn["weight_count"], pre_size * post_size)
        for _ in range(num_weights):
            if bit_width <= 8:
                buffer.write(struct.pack("b", 0))
            else:
                buffer.write(struct.pack("f", 0.0))

    return buffer.getvalue()


def generate_loihi_package(
    network: NetworkInput,
    bit_width: int = 8,
    board_id: str = "localhost",
    num_steps: int = 1000,
    progress_callback: Callable[[float, str], None] | None = None,
) -> bytes:
    """
    Generate a complete Loihi 2 NxSDK deployment package as a zip archive.

    Returns zip file content as bytes.
    """
    # Check cache
    cached = cache_manager.get_cached_artifact(
        network,
        "loihi",
        bit_width=bit_width,
        board_id=board_id,
        num_steps=num_steps,
    )
    if cached:
        if progress_callback:
            progress_callback(1.0, "Cache hit, returning artifact")
        return cached

    if progress_callback:
        progress_callback(0.1, "Starting Loihi package generation")

    template_dir = _get_template_dir()
    env = Environment(loader=FileSystemLoader(template_dir))

    if progress_callback:
        progress_callback(0.2, "Building template context")

    context = _build_template_context(network, bit_width, board_id, num_steps)

    if progress_callback:
        progress_callback(0.5, "Rendering templates and generating weights")

    # Render templates
    deploy_script = env.get_template("deploy.py.j2").render(context)
    config_json = env.get_template("config.json.j2").render(context)

    # Generate weight data
    weight_data = _generate_mock_hdf5_bytes(network, bit_width)

    if progress_callback:
        progress_callback(0.8, "Packaging into zip")

    # README
    readme = (
        f"# NeuroChip Loihi 2 Deployment Package\n\n"
        f"Auto-generated on {context['timestamp']}\n\n"
        f"## Prerequisites\n"
        f"- Intel NxSDK {context['nxsdk_version']}\n"
        f"- Access to INRC board\n"
        f"- Python 3.8+, h5py, numpy\n\n"
        f"## Files\n"
        f"- `deploy.py` — Main deployment script\n"
        f"- `config.json` — Board/run configuration\n"
        f"- `crossbar_weights.bin` — Quantized weight matrices\n\n"
        f"## Usage\n"
        f"```bash\n"
        f"python deploy.py --config config.json --timesteps {num_steps}\n"
        f"```\n\n"
        f"## Network Summary\n"
        f"- Neurons: {network.num_neurons}\n"
        f"- Synapses: {network.num_synapses}\n"
        f"- Weight bit-width: {bit_width}-bit\n"
        f"- Estimated cores: {context['num_cores']}\n"
    )

    # Create manifest
    checksum = hashlib.sha256(
        deploy_script.encode() + config_json.encode() + weight_data
    ).hexdigest()
    manifest = DeploymentManifest(
        target_device=TargetDevice.LOIHI_2,
        core_count=context["num_cores"],
        firmware_version="2.0.0",
        checksum_sha256=checksum,
    )

    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("loihi_deploy/deploy.py", deploy_script)
        zf.writestr("loihi_deploy/config.json", config_json)
        zf.writestr("loihi_deploy/crossbar_weights.bin", weight_data)
        zf.writestr("loihi_deploy/manifest.json", manifest.model_dump_json(indent=2))
        zf.writestr("loihi_deploy/README.md", readme)

    artifact = buffer.getvalue()

    if progress_callback:
        progress_callback(1.0, "Loihi package generation complete")

    # Store in cache
    cache_manager.cache_artifact(
        network,
        "loihi",
        artifact,
        bit_width=bit_width,
        board_id=board_id,
        num_steps=num_steps,
    )

    return artifact
