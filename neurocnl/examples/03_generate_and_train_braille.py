#!/usr/bin/env python3
"""
Example 3: Generate a Notebook from CNL and Actually Train It
================================================================

This is the full nmtk product pipeline exercised end to end, with no
FastAPI server, Docker, or Flutter app required:

    CNL spec text
        -> compile_to_nir()            (neurocnl.compile)
        -> _build_v2_notebook()        (backend.app.routers.notebook)
        -> real generated snnTorch training/eval code
        -> exec()'d for real, training on the bundled braille dataset

The CNL spec below defines a small 12-in / 48-hidden / 7-out feedforward
spiking network. Training and eval DAGs wire nmtk's own dataLoader ->
forwardPass -> loss -> backward -> optimiser nodes against the real
braille dataset already bundled at paper/03_rnn/data/*.pt (saved as
TensorDataset objects, which is exactly what the generated code's
format="pt" loader expects).

Usage:
    cd neurocnl && PYTHONPATH=. .venv/bin/python3 examples/03_generate_and_train_braille.py

Requires a venv with torch, snntorch, numpy, nir, fastapi, pydantic,
sse-starlette, slowapi, aiosqlite, structlog, prometheus-client, httpx,
and nengo installed (see neurocnl/AGENTS.md / repo AGENTS.md for the
suite's usual dependency set). The repo's default `.test-venv` does not
have torch; `neurocnl/.venv` is set up with a working one.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

# Script lives at neurocnl/examples/, backend/ and neurocnl/ are siblings
# one level up (this matches how neurocnl/backend/tests/ are run).
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
    _weights_artifact_name,
    compile_to_nir,
)

CNL_SPEC = "\n".join(
    [
        "Define a network named braille_feedforward with timestep 0.005.",
        "Define an input port named input with shape (12,).",
        "Define a linear transformation named w_input_hidden with weight matrix shape (48, 12).",
        "Define a LIF neuron named hidden"
        " with time constant 0.02, resistance 1.0, leak voltage 0.0,"
        " and firing threshold 1.0.",
        "Define a linear transformation named w_hidden_output with weight matrix shape (7, 48).",
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


def generate_notebook() -> tuple[dict, dict[str, bytes]]:
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
    nb, artifacts = _build_v2_notebook(CNL_SPEC, graph, cfg, timestamp, pipeline_phases=phases)
    return nb, artifacts


def write_outputs(nb: dict, artifacts: dict[str, bytes]) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    nb_path = OUTPUT_DIR / "braille_snntorch_demo.ipynb"
    nb_path.write_text(json.dumps(nb, indent=1))
    for name, content in artifacts.items():
        (OUTPUT_DIR / name).write_bytes(content)
    weights_name = _weights_artifact_name(CNL_SPEC, FRAMEWORK)
    print(f"Wrote {nb_path} (+ {len(artifacts)} artifact(s), e.g. {weights_name})")


def execute_notebook(nb: dict) -> list[dict]:
    """Exec every real generated code cell in order, capturing progress events.

    This runs the actual generated pipeline (not a stubbed test double) —
    the same code a user would get from ``uvx juv run`` or Jupyter, just
    executed directly in-process so this script can assert on the result.
    """
    import contextlib
    import io

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
                # UI-only "download as .py" helper cell — shells out to
                # `jupyter nbconvert`, irrelevant to verifying training.
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


def main() -> None:
    print("Generating notebook from CNL spec via nmtk's real codegen path...")
    nb, artifacts = generate_notebook()
    write_outputs(nb, artifacts)

    print(
        f"Executing {len([c for c in nb['cells'] if c['cell_type'] == 'code'])} generated code cells..."
    )
    events = execute_notebook(nb)

    train_events = [e for e in events if e.get("phase") == "train"]
    eval_events = [e for e in events if e.get("phase") == "eval"]

    print("Per-epoch train loss:", [round(e["loss"], 4) for e in train_events])
    chance = 1 / 7
    final_acc = eval_events[-1]["accuracy"] if eval_events else None
    print(f"Final eval accuracy: {final_acc} (chance = {chance:.4f})")

    if len(train_events) != EPOCHS:
        raise RuntimeError(f"Expected {EPOCHS} train progress events, got {len(train_events)}")
    first_loss = train_events[0]["loss"]
    last_loss = train_events[-1]["loss"]
    if not last_loss < first_loss:
        raise RuntimeError(f"Training loss did not decrease: first={first_loss} last={last_loss}")

    if final_acc is None or final_acc <= chance * 1.5:
        raise RuntimeError(
            f"Eval accuracy not clearly above chance ({chance:.1%}): got {final_acc}"
        )

    print("\n" + "=" * 60)
    print("Real training via nmtk's CNL -> notebook-codegen pipeline: PASSED")
    print(f"  Train loss:     {first_loss:.4f} -> {last_loss:.4f} over {EPOCHS} epochs")
    print(f"  Test accuracy:  {final_acc:.2%}  (chance = {chance:.2%})")
    print("=" * 60)


if __name__ == "__main__":
    main()
