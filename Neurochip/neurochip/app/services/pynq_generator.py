"""PYNQ artifact generation service — builds an overlay-v1 deployment ZIP.

Generates:
    pynq_deploy/
    ├── overlay_config.json   # Network topology + quantization parameters
    ├── weights.bin           # Packed quantized weights (int4/int8/int16)
    ├── register_map.json     # MMIO register layout for SNN overlay
    ├── overlay_manifest.json # Fixed overlay-v1 contract
    ├── manifest.json         # DeploymentManifest (target, version, checksum)
    └── README.md             # Auto-generated documentation

Follows the same artifact pattern as teensy_generator.py.
"""

import hashlib
import io
import json
import zipfile
from collections.abc import Callable
from datetime import datetime
from typing import Any

from ..._compat import UTC
from ...contracts.deployment_contracts import DeploymentManifest, TargetDevice
from ...contracts.pynq_runtime_artifact_contract import (
    CORE_COUNT,
    PynqOverlayConfigArtifactContract,
    PynqOverlayManifestContract,
)
from ..schemas.estimation import NetworkInput
from .cache_manager import cache_manager
from .pynq_overlay_manifest import load_design_overlay_manifest


def _build_overlay_config(
    network: NetworkInput,
    manifest: PynqOverlayManifestContract,
    bit_width: int,
    quantized_weights: list[Any] | None = None,
) -> dict[str, Any]:
    """Build the overlay_config.json content from a NetworkInput."""
    neuron_offset = 0
    pop_offsets: dict[str, int] = {}
    pop_sizes: dict[str, int] = {}
    populations: list[dict[str, Any]] = []

    for pop in network.populations:
        name = pop["name"]
        size = pop["size"]
        pop_offsets[name] = neuron_offset
        pop_sizes[name] = size
        neuron_offset += size

        populations.append(
            {
                "id": name,
                "n_neurons": size,
                "neuron_model": network.neuron_model.upper() if network.neuron_model else "LIF",
                "params": {
                    "tau_rc": 0.02,
                    "tau_ref": 0.002,
                    "v_threshold": 1.0,
                },
            }
        )

    connections: list[dict[str, Any]] = []
    weight_idx = 0

    for conn in network.connections:
        pre_name = conn["pre"]
        post_name = conn["post"]
        pre_size = pop_sizes.get(pre_name, 1)
        post_size = pop_sizes.get(post_name, 1)
        num_synapses = min(conn.get("weight_count", pre_size * post_size), pre_size * post_size)

        for i in range(num_synapses):
            w = 0
            if quantized_weights and (weight_idx + i) < len(quantized_weights):
                w = int(quantized_weights[weight_idx + i])
            connections.append(
                {
                    "pre": pre_name,
                    "post": post_name,
                    "weight": w,
                }
            )

        weight_idx += num_synapses

    # Compute scale factor for quantization
    max_range = (1 << (bit_width - 1)) - 1
    scale_factor = float(max_range) if max_range > 0 else 1.0

    return {
        "network_name": "pynq_snn_network",
        "populations": populations,
        "connections": connections,
        "quantisation": {
            "bits": bit_width,
            "scale_factor": scale_factor,
        },
        "overlay_id": manifest.overlay_id,
        "overlay_version": manifest.overlay_version,
    }


def _pack_weights(connections: list[dict[str, Any]], bit_width: int) -> bytes:
    """Pack connection weights into a binary blob.

    For int4: two 4-bit weights per byte (high nibble first).
    For int8: one weight per byte.
    For int16: two bytes per weight (little-endian).
    """
    weights = [int(c["weight"]) for c in connections]

    if bit_width == 4:
        packed = bytearray()
        for i in range(0, len(weights), 2):
            w1 = weights[i] & 0x0F
            w2 = (weights[i + 1] & 0x0F) if (i + 1) < len(weights) else 0
            packed.append((w1 << 4) | w2)
        return bytes(packed)

    elif bit_width == 8:
        return bytes(w & 0xFF for w in weights)

    else:  # 16-bit
        packed = bytearray()
        for w in weights:
            packed.extend((w & 0xFFFF).to_bytes(2, byteorder="little"))
        return bytes(packed)


def generate_pynq_package(
    network: NetworkInput,
    bit_width: int = 8,
    quantized_weights: list[Any] | None = None,
    progress_callback: Callable[[float, str], None] | None = None,
) -> bytes:
    """Generate a complete PYNQ deployment package as a ZIP archive.

    Parameters
    ----------
    network
        Validated network input with populations and connections.
    bit_width
        Weight quantization bit-width (4, 8, or 16).
    quantized_weights
        Optional pre-quantized weight list.
    progress_callback
        Optional ``(progress_fraction, message)`` callback.

    Returns
    -------
    bytes
        ZIP file content.
    """
    overlay_manifest = load_design_overlay_manifest()

    # Check cache
    cached = cache_manager.get_cached_artifact(
        network,
        "pynq",
        bit_width=bit_width,
        quantized_weights=quantized_weights,
        overlay_manifest=overlay_manifest.model_dump(),
    )
    if cached:
        if progress_callback:
            progress_callback(1.0, "Cache hit, returning artifact")
        return cached

    if progress_callback:
        progress_callback(0.1, "Starting PYNQ package generation")

    if bit_width not in overlay_manifest.supported_weight_bit_widths:
        raise ValueError(
            "PYNQ overlay-v1 only supports "
            f"{list(overlay_manifest.supported_weight_bit_widths)}-bit weights"
        )

    # 1. Build overlay config
    overlay_config = _build_overlay_config(network, overlay_manifest, bit_width, quantized_weights)
    PynqOverlayConfigArtifactContract.model_validate(overlay_config)

    if progress_callback:
        progress_callback(0.3, "Packing weights")

    # 2. Pack weights to binary
    weights_bin = _pack_weights(overlay_config["connections"], bit_width)

    if progress_callback:
        progress_callback(0.5, "Building register map and manifest")

    # 3. Register map and overlay manifest are sourced from overlay-v1
    register_map = overlay_manifest.register_map.model_dump()

    # 4. Build all text files
    timestamp = datetime.now(UTC).isoformat()
    total_neurons = sum(p["n_neurons"] for p in overlay_config["populations"])
    total_synapses = len(overlay_config["connections"])

    readme = (
        f"# NeuroChip PYNQ Deployment Package\n\n"
        f"Auto-generated on {timestamp}\n\n"
        f"## Target\n"
        f"- Board: PYNQ-Z2 (Zynq-7000)\n"
        f"- Cores: {CORE_COUNT}\n\n"
        f"## Network Summary\n"
        f"- Neurons: {total_neurons}\n"
        f"- Synapses: {total_synapses}\n"
        f"- Weight bit-width: {bit_width}-bit\n"
        f"- Neuron model: {network.neuron_model}\n\n"
        f"## Fixed Overlay Contract\n"
        f"- Overlay ID: {overlay_manifest.overlay_id}\n"
        f"- Overlay Version: {overlay_manifest.overlay_version}\n"
        f"- Target Part: {overlay_manifest.target_part}\n\n"
        f"## Package Contents\n"
        f"- `overlay_config.json` — Network topology and quantization parameters\n"
        f"- `weights.bin` — Packed quantized weight data\n"
        f"- `register_map.json` — MMIO register layout for the SNN overlay\n"
        f"- `overlay_manifest.json` — Fixed overlay-v1 hardware contract\n"
        f"- `manifest.json` — Deployment manifest with integrity checksum\n\n"
        f"## Deployment\n"
        f"1. Transfer this package to the PYNQ Z2 board\n"
        f"2. Load the overlay bitstream via the Neurochip PYNQ backend\n"
        f"3. The backend will write weights via MMIO and stream spikes via DMA\n"
    )

    files: dict[str, str | bytes] = {
        "pynq_deploy/overlay_config.json": json.dumps(overlay_config, indent=2),
        "pynq_deploy/register_map.json": json.dumps(register_map, indent=2),
        "pynq_deploy/overlay_manifest.json": overlay_manifest.model_dump_json(indent=2),
        "pynq_deploy/README.md": readme,
    }

    if progress_callback:
        progress_callback(0.7, "Computing checksums and packaging")

    # 5. Compute checksum over all text content + weights
    all_text = "".join(v if isinstance(v, str) else "" for v in files.values())
    checksum_input = all_text.encode() + weights_bin
    checksum = hashlib.sha256(checksum_input).hexdigest()

    # 6. Build deployment manifest
    manifest = DeploymentManifest(
        target_device=TargetDevice.PYNQ_Z2,
        core_count=CORE_COUNT,
        firmware_version="1.0.0",
        checksum_sha256=checksum,
    )
    files["pynq_deploy/manifest.json"] = manifest.model_dump_json(indent=2)

    # 7. Package into ZIP
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for path, content in files.items():
            if isinstance(content, bytes):
                zf.writestr(path, content)
            else:
                zf.writestr(path, content)
        zf.writestr("pynq_deploy/weights.bin", weights_bin)

    artifact = buffer.getvalue()

    if progress_callback:
        progress_callback(1.0, "PYNQ package generation complete")

    # 8. Cache for reuse
    cache_manager.cache_artifact(
        network,
        "pynq",
        artifact,
        bit_width=bit_width,
        quantized_weights=quantized_weights,
        overlay_manifest=overlay_manifest.model_dump(),
    )

    return artifact
