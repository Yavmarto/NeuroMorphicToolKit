# DeerFlow Context for Nengo-FPGA and SPA Integration
This document contains all the necessary file context required to implement the architectural plan.

## File: `docs/nengo_fpga_and_spa_plan.md`
```python
# Integration of Nengo-FPGA and Cognitive Architectures (SPA)

This document serves as the implementation plan for two major architectural expansions in the Neuromorphic Toolkit:
1. Integrating `nengo-fpga` into the Pynq Z2 end-to-end (e2e) pipeline.
2. Expanding the Computational Network Language (CNL) to support cognitive architectures and state machines via Nengo SPA.

## 1. Nengo-FPGA Pynq Pipeline

We have decided to relax the "standalone edge deployment" constraint in favor of using `nengo-fpga`, which will significantly speed up development velocity and stability. This means the Pynq board will be tethered to a host PC during execution to orchestrate the simulation.

### Implementation Steps

1. **New Exporter module**: Create `Neuro-Dream-Hand/neurodreamhand/hardware/nengo_fpga_exporter.py`.
   - This script will wrap target Nengo Ensembles in `nengo_fpga.FpgaPesEnsembleNetwork`.
   - It will manage the connection to the board over the network.
2. **Modify Deployment script**: Update `Neuro-Dream-Hand/scripts/step15_pynq_deployment.py`.
   - Add an argument flag `--use-nengo-fpga` to switch the deployment backend.
   - When enabled, instead of exporting quantized JSON (for FINN), it will invoke the `nengo_fpga_exporter.py` to prepare and run the network for tethered execution on the board.

---

## 2. Cognitive Architectures (NeuroCNL SPA)

To support state machines and cognitive architectures, we will map new CNL grammar constructs to Vector Symbolic Architectures (VSAs) using the standalone `nengo_spa` package.

### Natural Language Grammar for CNL
To maintain the "natural" requirements-driven structure of CNL (e.g., *The sensory neuron MUST fire...*), we will introduce new semantic rules that read like behavioral specifications.

**Examples of the new proposed SPA syntax:**
*   `The Vision memory MUST store 64 dimensional concepts` (Creates a `nengo_spa.State` or `nengo_spa.Buffer` with D=64)
*   `The Motor memory MUST store 64 dimensional concepts`
*   `The connection from Vision memory to Motor memory MUST transmit concepts` (Creates a simple `nengo_spa.Cortical` routing)
*   `The Basal Ganglia MUST route concepts from Vision memory to Motor memory ONLY IF the State memory contains the "REACH" concept` (Creates a `nengo_spa.Action` with condition gating)

### Implementation Steps

1. **Schema Expansion**: Modify `neurocnl/backend/app/schemas/` to parse these new natural language sentences and map them to structural nodes (`spa_buffer`, `spa_routing`, `spa_conditional_action`).
2. **Nengo Translation**: Modify `neurocnl/backend/app/services/nengo_code_exporter.py`.
   - Add support for `import nengo_spa as spa`.
   - Translate the new schema nodes to `nengo_spa` constructs (e.g., `nengo_spa.State`, `nengo_spa.Actions`).
3. **Unit Testing**: Create `neurocnl/tests/test_spa_compiler.py` to verify that the natural language specifications translate to executable Nengo SPA Python scripts without errors.

---

## Verification Plan

### Automated Tests
1. **CNL to SPA Compilation:** Run pytest on `test_spa_compiler.py` to ensure the generated Python script is syntactically valid and executes without Nengo errors.
2. **Grammar Integrity:** Ensure existing CNL tests pass without regression after expanding the grammar schema.

### Manual Verification
1. **Nengo-FPGA Hardware Test:** Deploy a simple test network onto the physical Pynq Z2 board using the new `nengo-fpga` tethered script, verify that the bitstream loads, and confirm the host PC can successfully communicate with the board.
2. **SPA Simulation:** Compile a simple CNL cognitive state machine, run the resulting Nengo SPA model locally (without FPGA), and verify the semantic pointers correctly transition states using the Nengo GUI.
```

## File: `Neuro-Dream-Hand/scripts/step15_pynq_deployment.py`
```python
"""Step 15 - PYNQ Z2 Deployment Configuration.

Usage::

    python step15_pynq_deployment.py --weights output/sleep_weights.npz

Output:
    output/pynq_config.json

Exports the trained SNN controller to a format suitable for PYNQ bitstream configuration.
"""

import argparse
from pathlib import Path

import numpy as np

from neurodreamhand.hardware.pynq_exporter import PYNQExporter


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export trained SNN weights to PYNQ Z2 configuration format."
    )
    parser.add_argument(
        "--weights", required=True, help="Path to .npz with trained decoder weights."
    )
    parser.add_argument(
        "--bits", type=int, default=8, help="Precision for weight quantization (bits)."
    )
    parser.add_argument(
        "--target-format",
        default="finn",
        help="Target compilation toolchain format (e.g., 'finn').",
    )
    args = parser.parse_args()

    # Load weights
    weights_path = Path(args.weights)
    if not weights_path.exists():
        raise FileNotFoundError(f"Weights file not found: {weights_path}")

    data = np.load(weights_path, allow_pickle=False)
    weights = data["weights"] if "weights" in data else data[data.files[0]]

    # Instantiate exporter
    exporter = PYNQExporter(weight_bits=args.bits, target_format=args.target_format)

    # Export config
    output_path = Path("output") / "pynq_config.json"
    exported_path = exporter.export_config(weights, output_path=output_path)

    print("\n--- PYNQ Deployment Export ---")
    print(f"  Input Weights:    {weights_path}")
    print(f"  Target Format:    {args.target_format}")
    print(f"  Quantization:     {args.bits}-bit INT")
    print(f"  Exported Config:  {exported_path}")


if __name__ == "__main__":
    main()
```

## File: `Neuro-Dream-Hand/neurodreamhand/hardware/pynq_exporter.py`
```python
"""PYNQ Overlay Exporter for Neuro-Dream-Hand.

This module provides utilities to export the NeuroCNL-compiled SNN graph,
specifically the quantized weights and network topology, into a format
suitable for PYNQ bitstream configuration (e.g., AXI initialization tables or
FINN dataflow configuration). It is intended to be used in the compilation
pipeline prior to deploying onto the FPGA fabric.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

import numpy as np

from neurodreamhand.hardware.quantization import quantize_weights

logger = logging.getLogger(__name__)


class PYNQExporter:
    """Exports SNN weights and configuration for PYNQ FPGA deployment.

    Takes a set of trained decoder weights and quantizes them to an integer
    format suitable for hardware synthesis (e.g., FINN-style dataflow compilation).
    Generates a configuration file containing the necessary metadata to configure
    the PYNQ overlay at runtime.

    Parameters
    ----------
    weight_bits : int
        The precision (in bits) to use for weight quantization.
        Defaults to 8 (INT8).
    target_format : str
        Identifier for the downstream compilation toolchain
        (e.g., "finn", "axi_table").
    """

    def __init__(
        self,
        *,
        weight_bits: int = 8,
        target_format: str = "finn",
    ) -> None:
        self.weight_bits = weight_bits
        self.target_format = target_format

    def export_config(
        self,
        weights: np.ndarray[Any, Any],
        output_path: str | Path = "output/pynq_config.json",
    ) -> Path:
        """Export quantized weights and network metadata to JSON.

        The resulting JSON file can be read by the downstream CHIP-004
        or CNL-054 compilation tools to generate the final `.bit` and `.hwh`
        files for the PYNQ overlay.

        Parameters
        ----------
        weights : np.ndarray
            The trained decoder weight matrix from the SNN controller.
        output_path : str or Path
            The destination path for the configuration JSON file.

        Returns
        -------
        Path
            The resolved path to the written JSON file.
        """
        path = Path(output_path).resolve()
        path.parent.mkdir(parents=True, exist_ok=True)

        # Quantize weights for hardware
        q_weights = quantize_weights(weights, n_bits=self.weight_bits)

        payload = {
            "metadata": {
                "target_format": self.target_format,
                "weight_bits": self.weight_bits,
                "shape": list(q_weights.shape),
                "original_w_max": float(np.max(np.abs(weights))),
                "original_w_min": float(np.min(np.abs(weights))),
            },
            # Convert numpy array to list for JSON serialization
            "weights": q_weights.tolist(),
        }

        with open(path, "w") as f:
            json.dump(payload, f, indent=2)

        logger.info("Exported PYNQ %s configuration to %s", self.target_format, path)
        return path
```

## File: `neurocnl/backend/app/services/nengo_code_exporter.py`
```python
"""Build a standalone Nengo script from a serialized graph."""

from __future__ import annotations

import re
from typing import Any


def export_nengo_code(graph: dict[str, list[dict[str, Any]]], label: str = "generated_network") -> str:
    """Render a deterministic Python script from a serialized network graph."""
    lines = [
        '"""Standalone Nengo script auto-generated by neurocnl."""',
        "",
        "import nengo",
        "import numpy as np",
        "",
        f"model = nengo.Network(label={label!r})",
        "with model:",
    ]

    declared_vars: dict[str, str] = {}
    used_vars: set[str] = set()
    connection_vars: dict[str, str] = {}

    for node in graph.get("nodes", []):
        node_id = str(node["id"])
        var_name = _python_identifier(node_id, used_vars)
        declared_vars[node_id] = var_name
        node_type = node.get("type")
        params = node.get("params", {})

        if node_type == "input_node":
            lines.append(f"    {var_name} = nengo.Node(0.0, label={node_id!r})")
            continue

        if node_type == "ensemble":
            n_neurons = int(params.get("n_neurons", 50))
            dimensions = int(params.get("dimensions", 1))
            tau_rc = float(params.get("tau_rc", 0.02))
            tau_ref = float(params.get("tau_ref", 0.002))
            neuron_type = params.get("neuron_type", "LIF")
            neuron_ctor = _neuron_type_ctor(neuron_type, tau_rc=tau_rc, tau_ref=tau_ref)
            lines.extend(
                [
                    f"    {var_name} = nengo.Ensemble(",
                    f"        n_neurons={n_neurons},",
                    f"        dimensions={dimensions},",
                    f"        neuron_type={neuron_ctor},",
                    f"        label={node_id!r},",
                    "    )",
                ]
            )
            continue

        lines.append(f"    # Unsupported node type {node_type!r} for {node_id!r}")

    if graph.get("edges"):
        lines.append("")

    deferred_edges: list[dict[str, Any]] = []
    for edge in graph.get("edges", []):
        source_id = str(edge["source"])
        target_id = str(edge["target"])
        source_var = declared_vars.get(source_id)
        target_var = declared_vars.get(target_id)

        if source_var is None or target_var is None:
            deferred_edges.append(edge)
            continue

        edge_var = _python_identifier(str(edge["id"]), used_vars)
        conn_args = [source_var, target_var]
        params = edge.get("params", {})
        transform = params.get("transform")
        synapse = params.get("synapse")

        if transform is not None:
            conn_args.append(f"transform={float(transform)!r}")
        if synapse is not None:
            conn_args.append(f"synapse=nengo.Lowpass({float(synapse)!r})")

        learning_rule = _learning_rule_ctor(edge)
        if learning_rule is not None:
            conn_args.append(f"learning_rule_type={learning_rule}")

        lines.append(f"    {edge_var} = nengo.Connection({', '.join(conn_args)})")
        connection_vars[str(edge["id"])] = edge_var

    if deferred_edges:
        lines.append("")
        emitted_header = False
        for edge in deferred_edges:
            source_id = str(edge["source"])
            target_id = str(edge["target"])
            source_var = declared_vars.get(source_id)
            base_connection_id = (
                target_id[: -len("_learning_rule")]
                if target_id.endswith("_learning_rule")
                else None
            )
            connection_var = (
                connection_vars.get(base_connection_id) if base_connection_id is not None else None
            )
            if source_var is not None and connection_var is not None:
                edge_var = _python_identifier(str(edge["id"]), used_vars)
                lines.append(
                    f"    {edge_var} = nengo.Connection({source_var}, {connection_var}.learning_rule)"
                )
                continue

            if not emitted_header:
                lines.append("    # Edges below could not be reconstructed as standalone nodes.")
                emitted_header = True
            lines.append(
                "    # Skipped edge: "
                f"{edge.get('source')!r} -> {edge.get('target')!r} "
                f"({edge.get('learning_rule') or 'static'})"
            )

    probe_targets = [node for node in graph.get("nodes", []) if node.get("type") == "ensemble"]
    if probe_targets:
        lines.append("")
        probe_vars: dict[str, str] = {}
        for node in probe_targets:
            node_id = str(node["id"])
            var_name = declared_vars[node_id]
            probe_var = _python_identifier(f"{node_id}_probe", used_vars)
            probe_vars[node_id] = probe_var
            lines.append(f"    {probe_var} = nengo.Probe({var_name}, synapse=0.01)")

        lines.extend(
            [
                "",
                "with nengo.Simulator(model) as sim:",
                "    sim.run(1.0)",
                "",
            ]
        )
        for node in probe_targets:
            node_id = str(node["id"])
            probe_var = probe_vars[node_id]
            lines.append(
                f"print({node_id!r}, np.asarray(sim.data[{probe_var}])[-1].tolist())"
            )
    else:
        lines.extend(
            [
                "",
                "with nengo.Simulator(model) as sim:",
                "    sim.run(1.0)",
            ]
        )

    return "\n".join(lines) + "\n"


def _learning_rule_ctor(edge: dict[str, Any]) -> str | None:
    rule_name = edge.get("learning_rule")
    if not edge.get("has_learning_rule") or not isinstance(rule_name, str):
        return None

    learning_rate = edge.get("learning_rate")
    suffix = f"(learning_rate={float(learning_rate)!r})" if learning_rate is not None else "()"
    if rule_name in {"PES", "BCM", "Oja"}:
        return f"nengo.{rule_name}{suffix}"
    return None


def _neuron_type_ctor(neuron_type: Any, *, tau_rc: float, tau_ref: float) -> str:
    if neuron_type == "AdaptiveLIF":
        return f"nengo.AdaptiveLIF(tau_rc={tau_rc!r}, tau_ref={tau_ref!r})"
    return f"nengo.LIF(tau_rc={tau_rc!r}, tau_ref={tau_ref!r})"


def _python_identifier(label: str, used: set[str], *, reserve: bool = True) -> str:
    identifier = re.sub(r"\W+", "_", label.strip().lower()).strip("_") or "node"
    if identifier[0].isdigit():
        identifier = f"node_{identifier}"

    candidate = identifier
    counter = 2
    while candidate in used:
        candidate = f"{identifier}_{counter}"
        counter += 1

    if reserve:
        used.add(candidate)
    return candidate
```

## File: `neurocnl/backend/app/schemas/parse.py`
```python
"""Pydantic models for the /api/parse endpoint."""

from pydantic import BaseModel

from backend.app.schemas.common import ErrorDetail


class ParsedSpec(BaseModel):
    concept: str
    subject: str
    action: str
    verb: str
    negated: bool
    condition: str | None = None
    shape: list[int] | None = None
    connectivity_pattern: str | None = None
    connectivity_mask: list[list[int]] | None = None
    locality_radius: float | None = None
    connection_density: float | None = None


class ParseSentence(BaseModel):
    line: int
    raw: str
    parsed: ParsedSpec | None = None
    valid: bool
    error: str | None = None
    error_detail: ErrorDetail | None = None


class ParseRequest(BaseModel):
    spec: str


class ParseResponse(BaseModel):
    sentences: list[ParseSentence]
    total: int
    errors: int
```

## File: `Neuro-Dream-Hand/cnl-specs/reflex_arc.cnl`
```python
The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds
The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0
The motor neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The motor neuron membrane potential MUST decay WITH time constant of 0.02 seconds
The connection from sensory neuron to motor neuron MUST transmit WITH synaptic weight of 15.0
```
