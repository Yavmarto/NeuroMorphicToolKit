#!/usr/bin/env python3
"""
Example 4: Full Pipeline Proof-of-Concept
==========================================

The simplest complete demonstration of nmtk's pipeline, all in one
script, no FastAPI server, Docker, or Flutter app required:

    CNL spec text
        -> compile_to_nir()                              (Step 1: Compile)
        -> NIR_CNL_Parser + layer1/2 validate_nir_records (Step 2: Validate)
        -> generate_default_stimulus + SnnTorchSimulatorAdapter
                                                           (Step 3: Simulate)
        -> _build_v2_notebook() + exec() (real training)  (Step 4: Train + Eval)
        -> nir.write() + NengoIO().from_nir()             (Step 5: Export)

Reuses example 3's exact CNL spec (12-in / 48-hidden / 7-out feedforward
SNN) and the bundled braille dataset at paper/03_rnn/data/*.pt — already
proven to compile, validate, simulate, and train correctly, so this
script can focus on showing every pipeline stage rather than re-deriving
a new toy problem.

Note: hardware deploy (Teensy/PYNQ/Lava/Akida, backend/app/routers/deploy.py)
is NOT reachable from this NIR-native graph today — that deploy path only
operates on the separate legacy MUST/WITH grammar. Step 5 instead exports
a portable `.nir` file and generated Nengo Python code, both of which need
nothing beyond this script's own dependencies.

Usage:
    cd neurocnl && PYTHONPATH=. .venv/bin/python3 examples/04_full_pipeline_poc.py

Requires the same venv as example 3 (torch, snntorch, numpy, nir, fastapi,
pydantic, sse-starlette, slowapi, aiosqlite, structlog, prometheus-client,
httpx, nengo) — see `neurocnl/.venv`.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import nir

NEUROCNL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(NEUROCNL_ROOT))

REPO_ROOT = NEUROCNL_ROOT.parent
DATA_DIR = REPO_ROOT / "paper" / "03_rnn" / "data"
OUTPUT_DIR = Path(__file__).resolve().parent / "output"

from backend.app.routers.notebook import DagNodePayload  # noqa: E402
from backend.app.routers.notebook import (
    PhaseDAGPayload,
    PipelineConfigPayload,
    PipelinePhasesPayload,
    _build_v2_notebook,
    compile_to_nir,
)
from neurocnl.converter.nengo_io import NengoIO  # noqa: E402
from neurocnl.layers.layer1_validator import (
    validate_nir_records as layer1_validate_nir_records,
)

# noqa: E402
from neurocnl.layers.layer2_validator import (
    validate_nir_records as layer2_validate_nir_records,
)

# noqa: E402
from neurocnl.nir_cnl.parser import NIR_CNL_Parser  # noqa: E402
from neurocnl.runtime.snntorch_simulator import SnnTorchSimulatorAdapter  # noqa: E402
from neurocnl.runtime.stimulus import generate_default_stimulus  # noqa: E402

CNL_SPEC = "\n".join(
    [
        "Define a network named braille_feedforward with timestep 0.005.",
        "Define an input port named input with shape (12,).",
        "Define a linear transformation named w_input_hidden with weight matrix shape (48, 12)"
        ' annotated with metadata weight_init equal to "xavier"'
        " annotated with metadata seed equal to 42.",
        "Define a LIF neuron named hidden"
        " with time constant 0.02, resistance 1.0, leak voltage 0.0,"
        " and firing threshold 1.0.",
        "Define a linear transformation named w_hidden_output with weight matrix shape (7, 48)"
        ' annotated with metadata weight_init equal to "xavier"'
        " annotated with metadata seed equal to 43.",
        "Define a LIF neuron named output_layer"
        " with time constant 0.02, resistance 1.0, leak voltage 0.0,"
        " and firing threshold 1.0.",
        "Define an output port named output with shape (7,).",
        "input connects to w_input_hidden.",
        "w_input_hidden connects to hidden.",
        "hidden connects to w_hidden_output.",
        "w_hidden_output connects to output_layer.",
        "output_layer connects to output.",
    ]
)

EPOCHS = 30
BATCH_SIZE = 32
FRAMEWORK = "snntorch_sim"
SIM_TIMESTEPS = 50
SIM_SEED = 42


def step1_compile() -> tuple[nir.NIRGraph, dict]:
    print("\n--- Step 1: Compile ---")
    graph = compile_to_nir(CNL_SPEC)
    n_nodes, n_edges = len(graph.nodes), len(graph.edges)
    print(f"Compiled graph: {n_nodes} nodes, {n_edges} edges")
    if n_nodes == 0 or n_edges == 0:
        raise RuntimeError(f"Compiled graph is empty: nodes={n_nodes} edges={n_edges}")
    return graph, {"nodes": n_nodes, "edges": n_edges}


def step2_validate() -> dict:
    print("\n--- Step 2: Validate ---")
    records = NIR_CNL_Parser().parse(CNL_SPEC)
    layer1 = layer1_validate_nir_records(records, backend="nengo")
    layer2 = layer2_validate_nir_records(records)
    print(f"Layer 1: {len(layer1['passed'])} passed, {len(layer1['failed'])} failed")
    print(
        f"Layer 2: {len(layer2['checks_passed'])} checks passed, "
        f"{len(layer2['checks_failed'])} checks failed"
    )
    if not layer1["overall"]:
        print("Layer 1 failures:", layer1["failed"])
        raise RuntimeError("Layer 1 (physical invariant) validation failed")
    if not layer2["overall"]:
        print("Layer 2 failures:", layer2["checks_failed"])
        raise RuntimeError("Layer 2 (cross-record consistency) validation failed")
    return {
        "layer1_passed": len(layer1["passed"]),
        "layer1_failed": len(layer1["failed"]),
        "layer2_checks_passed": len(layer2["checks_passed"]),
        "layer2_checks_failed": len(layer2["checks_failed"]),
    }


def step3_simulate(graph: nir.NIRGraph) -> dict:
    print("\n--- Step 3: Simulate (pre-training sanity check) ---")
    stimulus = generate_default_stimulus(graph, timesteps=SIM_TIMESTEPS, seed=SIM_SEED)
    result = SnnTorchSimulatorAdapter().run(graph, stimulus, timesteps=SIM_TIMESTEPS, seed=SIM_SEED)
    total_spikes = sum(len(times) for pop in result.spikes.values() for times in pop.values())
    total_neurons = sum(len(pop) for pop in result.spikes.values())
    firing_rate = total_spikes / (SIM_TIMESTEPS * total_neurons) if total_neurons else 0.0
    print(
        f"Total spikes over {SIM_TIMESTEPS} timesteps: {total_spikes} "
        f"(firing rate {firing_rate:.2%})"
    )
    if result.warnings:
        print("Simulator warnings:", result.warnings)
    if total_spikes == 0:
        raise RuntimeError(
            "Network produced zero spikes with fixed (untrained) weights — "
            "this is the exact 'dead network' failure mode a missing/unreachable "
            "LIF firing threshold produces. Check the CNL spec's declared "
            "network timestep and neuron parameters."
        )
    return {
        "timesteps": SIM_TIMESTEPS,
        "total_spikes": total_spikes,
        "firing_rate": firing_rate,
        "warnings": result.warnings,
    }


def _build_pipeline_phases() -> PipelinePhasesPayload:
    train_phase = PhaseDAGPayload(
        nodes=[
            DagNodePayload(
                id="t1",
                type="dataLoader",
                parameters={
                    "format": "pt",
                    "dataset_path": str(DATA_DIR / "ds_train.pt"),
                    "batch_size": BATCH_SIZE,
                },
            ),
            DagNodePayload(id="t2", type="forwardPass", parameters={}),
            DagNodePayload(id="t3", type="ceCountLoss", parameters={}),
            DagNodePayload(
                id="t4",
                type="surrogateBackward",
                parameters={"function": "fast_sigmoid", "slope": 5.0},
            ),
            DagNodePayload(id="t5", type="adamOptimiser", parameters={"lr": 0.001}),
        ],
        edges=[],
    )
    eval_phase = PhaseDAGPayload(
        nodes=[
            DagNodePayload(
                id="e1",
                type="dataLoader",
                parameters={
                    "format": "pt",
                    "dataset_path": str(DATA_DIR / "ds_test.pt"),
                    "batch_size": BATCH_SIZE,
                },
            ),
            DagNodePayload(id="e2", type="forwardPass", parameters={}),
            DagNodePayload(id="e3", type="accuracyMetric", parameters={}),
        ],
        edges=[],
    )
    return PipelinePhasesPayload(train=train_phase, eval=eval_phase)


def _generate_notebook() -> tuple[dict, dict[str, bytes]]:
    graph = compile_to_nir(CNL_SPEC)
    cfg = PipelineConfigPayload(
        dataset="custom",
        framework=FRAMEWORK,
        epochs=EPOCHS,
        seed=42,
        batch_size=BATCH_SIZE,
        learning_rate=0.001,
        optimizer="Adam",
        run_evaluation=True,
    )
    phases = _build_pipeline_phases()
    timestamp = time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime())
    return _build_v2_notebook(CNL_SPEC, graph, cfg, timestamp, pipeline_phases=phases)


def _write_notebook_outputs(nb: dict, artifacts: dict[str, bytes]) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    nb_path = OUTPUT_DIR / "pipeline_poc_demo.ipynb"
    nb_path.write_text(json.dumps(nb, indent=1))
    for name, content in artifacts.items():
        (OUTPUT_DIR / name).write_bytes(content)
    return nb_path


def _execute_notebook(nb: dict) -> list[dict]:
    """Exec every real generated code cell in order, capturing progress events."""
    import contextlib
    import io
    import os

    prev_cwd = os.getcwd()
    os.chdir(OUTPUT_DIR)
    exec_globals: dict = {}
    progress_events: list[dict] = []
    buf = io.StringIO()
    try:
        for i, cell in enumerate(nb["cells"]):
            if cell["cell_type"] != "code":
                continue
            src = "".join(cell["source"])
            if "nbconvert" in src:
                continue
            buf.truncate(0)
            buf.seek(0)
            try:
                with contextlib.redirect_stdout(buf):
                    exec(compile(src, f"<generated-cell-{i}>", "exec"), exec_globals)
            except Exception:
                print(f"--- failing cell {i} ---\n{src}\n---")
                raise
            for line in buf.getvalue().splitlines():
                line = line.strip()
                if not line.startswith("{"):
                    continue
                try:
                    evt = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if evt.get("__nmtk_progress__"):
                    progress_events.append(evt)
    finally:
        os.chdir(prev_cwd)
    return progress_events


def step4_train_eval() -> dict:
    print("\n--- Step 4: Train + Eval ---")
    nb, artifacts = _generate_notebook()
    nb_path = _write_notebook_outputs(nb, artifacts)
    print(f"Wrote {nb_path} (+ {len(artifacts)} artifact(s))")

    events = _execute_notebook(nb)
    train_events = [e for e in events if e.get("phase") == "train"]
    eval_events = [e for e in events if e.get("phase") == "eval"]

    loss_curve = [round(e["loss"], 4) for e in train_events]
    chance = 1 / 7
    final_acc = eval_events[-1]["accuracy"] if eval_events else None
    print("Per-epoch train loss:", loss_curve)
    print(f"Final eval accuracy: {final_acc} (chance = {chance:.4f})")

    if len(train_events) != EPOCHS:
        raise RuntimeError(f"Expected {EPOCHS} train progress events, got {len(train_events)}")
    first_loss, last_loss = train_events[0]["loss"], train_events[-1]["loss"]
    if not last_loss < first_loss:
        raise RuntimeError(f"Training loss did not decrease: first={first_loss} last={last_loss}")
    if final_acc is None or final_acc <= chance * 1.5:
        raise RuntimeError(
            f"Eval accuracy not clearly above chance ({chance:.1%}): got {final_acc}"
        )
    return {
        "epochs": EPOCHS,
        "loss_curve": loss_curve,
        "final_accuracy": final_acc,
        "chance": chance,
    }


def step5_export(graph: nir.NIRGraph) -> dict:
    print("\n--- Step 5: Deploy / Export capstone ---")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    nir_path = OUTPUT_DIR / "braille_feedforward.nir"
    compile_to_nir(CNL_SPEC, save_to=nir_path)

    nengo_code = NengoIO().from_nir(graph)
    nengo_path = OUTPUT_DIR / "braille_feedforward_nengo.py"
    nengo_path.write_text(nengo_code)

    nir_bytes = nir_path.stat().st_size
    nengo_bytes = nengo_path.stat().st_size
    print(f"Wrote {nir_path} ({nir_bytes} bytes)")
    print(f"Wrote {nengo_path} ({nengo_bytes} bytes)")
    print(
        "Note: hardware deploy (Teensy/PYNQ/Lava/Akida) is not reachable from "
        "this NIR-native graph today — it operates on a separate legacy "
        "grammar. The .nir file and generated Nengo code above are this "
        "POC's portable, runnable deploy artifacts."
    )
    if nir_bytes == 0 or nengo_bytes == 0:
        raise RuntimeError("Export produced an empty file")
    return {
        "nir_path": str(nir_path),
        "nir_bytes": nir_bytes,
        "nengo_code_path": str(nengo_path),
        "nengo_code_bytes": nengo_bytes,
    }


def main() -> None:
    graph, compile_report = step1_compile()
    validate_report = step2_validate()
    simulate_report = step3_simulate(graph)
    train_eval_report = step4_train_eval()
    export_report = step5_export(graph)

    report = {
        "compile": compile_report,
        "validate": validate_report,
        "simulate": simulate_report,
        "train_eval": train_eval_report,
        "export": export_report,
    }
    report_path = OUTPUT_DIR / "pipeline_report.json"
    report_path.write_text(json.dumps(report, indent=2))

    print("\n" + "=" * 60)
    print("ALL 5 STEPS PASSED — full nmtk pipeline proof-of-concept")
    print("=" * 60)
    print(f"  1. Compile:      {compile_report['nodes']} nodes, {compile_report['edges']} edges")
    print(
        f"  2. Validate:     L1 {validate_report['layer1_passed']} passed / "
        f"L2 {validate_report['layer2_checks_passed']} checks passed, 0 failures"
    )
    print(
        f"  3. Simulate:     {simulate_report['total_spikes']} spikes "
        f"({simulate_report['firing_rate']:.2%} firing rate)"
    )
    print(
        f"  4. Train + Eval: loss {train_eval_report['loss_curve'][0]:.4f} -> "
        f"{train_eval_report['loss_curve'][-1]:.4f}, "
        f"accuracy {train_eval_report['final_accuracy']:.2%} "
        f"(chance {train_eval_report['chance']:.2%})"
    )
    print(
        f"  5. Export:       {export_report['nir_bytes']} byte .nir file, "
        f"{export_report['nengo_code_bytes']} byte Nengo code"
    )
    print(f"\nFull report written to {report_path}")
    print("=" * 60)


if __name__ == "__main__":
    main()
