"""Teensy firmware generation service — renders Jinja2 templates into a complete project."""

import hashlib
import io
import math
import os
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
        os.path.dirname(os.path.abspath(__file__)), "..", "..", "firmware_templates", "teensy"
    )


def _coerce_weight_for_storage(weight: float, bit_width: int) -> float | int:
    """Convert raw connection weights to the storage format used by the template."""
    if bit_width <= 16:
        max_int = (2 ** (bit_width - 1)) - 1
        clipped = max(-1.0, min(1.0, weight))
        return int(round(clipped * max_int))
    return weight


def _build_template_context(
    network: NetworkInput,
    bit_width: int = 8,
    quantized_weights: list[Any] | None = None,
    input_pins: list[int] | None = None,
    output_pins: list[int] | None = None,
    debug_serial: bool = True,
) -> dict[str, Any]:
    """Build the context dict for Jinja2 template rendering."""
    dt_ms = 1
    dt_seconds = dt_ms / 1000.0

    # Build synapse list from connections
    neuron_offset = 0
    pop_offsets = {}
    pop_sizes = {}
    pop_thresholds = {}
    pop_tau_decay = {}
    pop_refractory_steps = {}

    for pop in network.populations:
        pop_offsets[pop["name"]] = neuron_offset
        pop_sizes[pop["name"]] = pop["size"]
        pop_thresholds[pop["name"]] = float(pop.get("threshold", 1.0))
        tau_rc = float(pop.get("tau_rc", 0.02))
        pop_tau_decay[pop["name"]] = math.exp(-dt_seconds / tau_rc)
        tau_ref = float(pop.get("tau_ref", 0.002))
        pop_refractory_steps[pop["name"]] = max(0, round(tau_ref / dt_seconds))
        neuron_offset += pop["size"]

    synapses = []
    weight_idx = 0
    max_delay_steps = 1
    for conn in network.connections:
        pre_offset = pop_offsets.get(conn["pre"], 0)
        post_offset = pop_offsets.get(conn["post"], 0)
        pre_size = pop_sizes.get(conn["pre"], 1)
        post_size = pop_sizes.get(conn["post"], 1)
        raw_weight = float(conn.get("weight", 0))
        stored_weight = _coerce_weight_for_storage(raw_weight, bit_width)
        delay_seconds = float(conn.get("delay", 0.001))
        delay_steps = max(1, round(delay_seconds / dt_seconds))
        max_delay_steps = max(max_delay_steps, delay_steps)

        num_synapses = min(conn["weight_count"], pre_size * post_size)

        # Optimize by using a list comprehension for synapse generation
        if quantized_weights:
            conn_synapses = [
                {
                    "pre": pre_offset + (i % pre_size),
                    "post": post_offset + (i // pre_size) % post_size,
                    "weight": quantized_weights[weight_idx + i]
                    if (weight_idx + i) < len(quantized_weights)
                    else stored_weight,
                    "delay_steps": delay_steps,
                }
                for i in range(num_synapses)
            ]
        else:
            conn_synapses = [
                {
                    "pre": pre_offset + (i % pre_size),
                    "post": post_offset + (i // pre_size) % post_size,
                    "weight": stored_weight,
                    "delay_steps": delay_steps,
                }
                for i in range(num_synapses)
            ]

        synapses.extend(conn_synapses)
        weight_idx += num_synapses

    # Determine input/output neuron IDs (first and last populations)
    input_pop: dict[str, Any] = (
        network.populations[0] if network.populations else {"name": "in", "size": 1}
    )
    output_pop: dict[str, Any] = (
        network.populations[-1] if network.populations else {"name": "out", "size": 1}
    )

    input_neuron_ids = list(
        range(
            pop_offsets.get(input_pop["name"], 0),
            pop_offsets.get(input_pop["name"], 0) + int(input_pop["size"]),
        )
    )
    output_neuron_ids = list(
        range(
            pop_offsets.get(output_pop["name"], 0),
            pop_offsets.get(output_pop["name"], 0) + int(output_pop["size"]),
        )
    )

    thresholds = [1.0] * network.num_neurons
    tau_values = [math.exp(-dt_seconds / 0.02)] * network.num_neurons
    refractory_steps = [round(0.002 / dt_seconds)] * network.num_neurons
    for pop in network.populations:
        start = pop_offsets.get(pop["name"], 0)
        end = start + int(pop["size"])
        thresholds[start:end] = [pop_thresholds[pop["name"]]] * int(pop["size"])
        tau_values[start:end] = [pop_tau_decay[pop["name"]]] * int(pop["size"])
        refractory_steps[start:end] = [pop_refractory_steps[pop["name"]]] * int(pop["size"])

    return {
        "network_name": "SNN Network",
        "timestamp": datetime.now(UTC).isoformat(),
        "bit_width": bit_width,
        "num_neurons": network.num_neurons,
        "num_synapses": len(synapses),
        "num_inputs": len(input_neuron_ids),
        "num_outputs": len(output_neuron_ids),
        "input_neuron_ids": input_neuron_ids,
        "output_neuron_ids": output_neuron_ids,
        "synapses": synapses,
        "thresholds": thresholds,
        "tau_values": tau_values,
        "refractory_steps": refractory_steps,
        "weights": [s["weight"] for s in synapses],
        "synapse_delay_steps": [s["delay_steps"] for s in synapses],
        "input_pins": input_pins or [],
        "output_pins": output_pins or [],
        "debug_serial": debug_serial,
        "dt_ms": dt_ms,
        "v_threshold": 1.0,
        "v_reset": 0.0,
        "max_delay_steps": max_delay_steps,
    }


def generate_teensy_project(
    network: NetworkInput,
    bit_width: int = 8,
    quantized_weights: list[Any] | None = None,
    input_pins: list[int] | None = None,
    output_pins: list[int] | None = None,
    progress_callback: Callable[[float, str], None] | None = None,
) -> bytes:
    """
    Generate a complete Teensy firmware project as a zip archive.

    Returns the zip file content as bytes.
    """
    # Check cache
    cached = cache_manager.get_cached_artifact(
        network,
        "teensy",
        bit_width=bit_width,
        quantized_weights=quantized_weights,
        input_pins=input_pins,
        output_pins=output_pins,
    )
    if cached:
        if progress_callback:
            progress_callback(1.0, "Cache hit, returning artifact")
        return cached

    if progress_callback:
        progress_callback(0.1, "Starting Teensy project generation")

    template_dir = _get_template_dir()
    env = Environment(loader=FileSystemLoader(template_dir))

    if progress_callback:
        progress_callback(0.2, "Building template context")

    context = _build_template_context(
        network, bit_width, quantized_weights, input_pins, output_pins
    )

    if progress_callback:
        progress_callback(0.5, "Rendering templates")

    # Render templates
    files = {
        "neurochip_firmware/src/main.ino": env.get_template("main.ino.j2").render(context),
        "neurochip_firmware/src/network_params.h": env.get_template("network_params.h.j2").render(
            context
        ),
        "neurochip_firmware/src/lif_engine.h": env.get_template("lif_engine.h.j2").render(context),
        "neurochip_firmware/platformio.ini": env.get_template("platformio.ini.j2").render(context),
    }

    if progress_callback:
        progress_callback(0.8, "Packaging into zip")

    # Add a README
    files["neurochip_firmware/README.md"] = (
        f"# NeuroChip Teensy Firmware\n\n"
        f"Auto-generated on {context['timestamp']}\n\n"
        f"## Network Summary\n"
        f"- Neurons: {context['num_neurons']}\n"
        f"- Synapses: {context['num_synapses']}\n"
        f"- Weight bit-width: {bit_width}-bit\n\n"
        f"## How to Compile\n"
        f"1. Install [PlatformIO](https://platformio.org/install)\n"
        f"2. `cd neurochip_firmware && pio run`\n\n"
        f"## How to Flash\n"
        f"1. Connect Teensy 4.1 via USB\n"
        f"2. `pio run --target upload`\n\n"
        f"## Pin Mappings\n"
        f"- Input pins: {context['input_pins'] or 'None configured'}\n"
        f"- Output pins: {context['output_pins'] or 'None configured'}\n"
    )

    # Create manifest
    all_content = "".join(files.values())
    checksum = hashlib.sha256(all_content.encode()).hexdigest()
    manifest = DeploymentManifest(
        target_device=TargetDevice.TEENSY_41,
        core_count=1,
        firmware_version="1.0.0",
        checksum_sha256=checksum,
    )
    files["neurochip_firmware/manifest.json"] = manifest.model_dump_json(indent=2)

    # Package into zip
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for path, content in files.items():
            zf.writestr(path, content)

    artifact = buffer.getvalue()

    if progress_callback:
        progress_callback(1.0, "Teensy project generation complete")

    # Store in cache
    cache_manager.cache_artifact(
        network,
        "teensy",
        artifact,
        bit_width=bit_width,
        quantized_weights=quantized_weights,
        input_pins=input_pins,
        output_pins=output_pins,
    )

    return artifact
