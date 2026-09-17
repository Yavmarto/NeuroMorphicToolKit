"""Shared fixtures/helpers for the notebook test suite (split out of
the former ``test_notebook_generate_v2.py``). Not collected by pytest
directly (the filename does not match ``test_*.py``) — test modules
import what they need from here.
"""

from __future__ import annotations

import base64
from pathlib import Path
from typing import Any
from unittest.mock import patch

import nir
import numpy as np
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.routers.notebook import (
    PhaseDAGPayload,
    PipelineConfigPayload,
    PipelinePhasesPayload,
    _build_v2_notebook,
)
from neurocnl._nir_compat import make_nir_graph
from neurocnl.runtime.cnl_nodes import RSynaptic as CnlRSynaptic
from neurocnl.runtime.cnl_nodes import Synaptic as CnlSynaptic

client = TestClient(app)


# `paper/` lives at the suite root, two levels above this checkout's `backend/`
# — anchor it to this file so these tests pass regardless of pytest's cwd.
CNN_SINABS_NIR = (
    Path(__file__).resolve().parents[3] / "paper" / "02_cnn" / "cnn_sinabs.nir"
)


# A complete NIR-native spec that compiles cleanly via compile_to_nir.
# Kept identical to the fixture in test_generate_router.py so both suites
# exercise the same known-good parse path.
VALID_SPEC = "\n".join(
    [
        "Define a network named feedforward.",
        "Define an input port named input with shape (4,).",
        "Define a linear transformation named w_input_hidden with weight matrix shape (3, 4).",
        "Define a LIF neuron named hidden"
        " with time constant 0.02, resistance 1.0, leak voltage 0.0,"
        " and firing threshold 1.0.",
        "Define a linear transformation named w_hidden_output with weight matrix shape (2, 3).",
        "Define a LIF neuron named output_layer"
        " with time constant 0.02, resistance 1.0, leak voltage 0.0,"
        " and firing threshold 1.0.",
        "Define an output port named output with shape (2,).",
        "input connects to w_input_hidden.",
        "w_input_hidden connects to hidden.",
        "hidden connects to w_hidden_output.",
        "w_hidden_output connects to output_layer.",
        "output_layer connects to output.",
    ]
)


def _braille_training_phase() -> PhaseDAGPayload:
    from backend.app.routers.notebook import DagNodePayload, PhaseDAGPayload

    return PhaseDAGPayload(
        nodes=[
            DagNodePayload(id="t1", type="dataLoader", parameters={"batch_size": 32}),
            DagNodePayload(id="t2", type="stateReset", parameters={}),
            DagNodePayload(id="t3", type="forwardPass", parameters={}),
            DagNodePayload(id="t4", type="ceCountLoss", parameters={}),
            DagNodePayload(id="t5", type="surrogateBackward", parameters={}),
            DagNodePayload(id="t6", type="adamOptimiser", parameters={"lr": 0.001}),
        ],
        edges=[],
    )


def _build_nb_for(
    framework: str, run_evaluation: bool = True, export_nir: bool = False
):
    """Build a v2 notebook for the given framework and return all code cell sources joined."""
    from neurocnl.compile import compile_to_nir

    graph = compile_to_nir(VALID_SPEC)
    cfg = PipelineConfigPayload(
        framework=framework,
        run_evaluation=run_evaluation,
        export_nir=export_nir,
    )
    nb, _ = _build_v2_notebook(
        VALID_SPEC,
        graph,
        cfg,
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )
    return nb, graph


def _code_sources(nb: dict) -> str:
    return " ".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "code"
    )


def _cell_after_md(nb: dict, md_heading: str) -> str:
    """Return the source of the code cell immediately after a markdown heading."""
    cells = nb["cells"]
    for i, c in enumerate(cells):
        if c["cell_type"] == "markdown" and md_heading in "".join(c["source"]):
            for j in range(i + 1, len(cells)):
                if cells[j]["cell_type"] == "code":
                    return "".join(cells[j]["source"])
    return ""


def _second_code_after_md(nb: dict, md_heading: str) -> str:
    """Return the second code cell after a markdown heading, if present."""
    cells = nb["cells"]
    code_cells_seen = 0
    for i, c in enumerate(cells):
        if c["cell_type"] == "markdown" and md_heading in "".join(c["source"]):
            for j in range(i + 1, len(cells)):
                if cells[j]["cell_type"] != "code":
                    continue
                code_cells_seen += 1
                if code_cells_seen == 2:
                    return "".join(cells[j]["source"])
    return ""


def _build_nb_for_braille(framework: str) -> dict:
    from backend.tests.notebook_test_fixtures import _braille_nir_graph

    nb, _ = _build_v2_notebook(
        "",
        _braille_nir_graph(),
        PipelineConfigPayload(framework=framework),
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )
    return nb


def _generate_v2(framework: str, tmp_path: Path) -> dict:
    """POST /notebook/generate-v2 for one framework, returning the JSON body."""
    with (
        patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path),
        patch("backend.app.routers.notebook.JUPYTER_WORKER_URL", ""),
    ):
        response = client.post(
            "/api/notebook/generate-v2",
            json={
                "spec": VALID_SPEC,
                "pipeline_config": {"framework": framework},
                "pipeline_phases": {
                    "train": {"nodes": [{"id": "forward", "type": "forwardPass"}]},
                },
            },
        )
    assert response.status_code == 200, response.text
    return response.json()


def _unsupported_type_graph() -> nir.NIRGraph:
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "flat": nir.Flatten(
                input_type={"input": np.array([2])},
                start_dim=1,
                end_dim=-1,
            ),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "flat"), ("flat", "output")],
        type_check=False,
    )


# A structurally different feedforward network (different weight-matrix
# shapes and layer names) from VALID_SPEC, so both the generated code and
# the weight content are clearly distinguishable between the two specs.
RESHAPED_SPEC = "\n".join(
    [
        "Define a network named feedforward2.",
        "Define an input port named input with shape (5,).",
        "Define a linear transformation named w_solo with weight matrix shape (3, 5).",
        "Define a LIF neuron named solo_layer"
        " with time constant 0.02, resistance 1.0, leak voltage 0.0,"
        " and firing threshold 1.0.",
        "Define an output port named output with shape (3,).",
        "input connects to w_solo.",
        "w_solo connects to solo_layer.",
        "solo_layer connects to output.",
    ]
)


class _FakeJupyterContents:
    """Minimal Jupyter Contents API stand-in for one bundle in one folder.

    Serves `content` the way the real server does — base64 **wrapped across
    lines** — which is the whole point: every test before this one exercised the
    local-glob branch (`JUPYTER_WORKER_URL: ""`), so the Jupyter branch's
    decode was uncovered and shipped raising `binascii.Error` as a bare 500.
    """

    def __init__(self, payload: bytes, filename: str = "model.akida-bundle.zip"):
        self._payload = payload
        self._filename = filename

    def __call__(self, *args, **kwargs):
        return self

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def get(self, url: str):
        import textwrap

        body: dict[str, Any]
        if url.endswith(self._filename):
            wrapped = "\n".join(
                textwrap.wrap(base64.b64encode(self._payload).decode("ascii"), 76)
            )
            body = {"format": "base64", "content": wrapped}
        else:
            body = {
                "content": [
                    {
                        "name": self._filename,
                        "last_modified": "2026-08-06T10:00:00Z",
                    }
                ]
            }
        return type("_Response", (), {"status_code": 200, "json": lambda _self: body})()


SMALL_LIF_FIRST_SPEC = "\n".join(
    [
        "Define a network named bringup.",
        "Define an input port named input with shape (32,).",
        "Define a LIF neuron named lif_in"
        " with time constant 0.02, resistance 1.0, leak voltage 0.0,"
        " and firing threshold 1.0.",
        "Define a linear transformation named w_out with weight matrix shape (4, 32).",
        "Define a LIF neuron named lif_out"
        " with time constant 0.02, resistance 1.0, leak voltage 0.0,"
        " and firing threshold 1.0.",
        "Define an output port named output with shape (4,).",
        "input connects to lif_in.",
        "lif_in connects to w_out.",
        "w_out connects to lif_out.",
        "lif_out connects to output.",
    ]
)


def _pt_loader_phases(dataset_path: str) -> dict:
    return {
        "train": {
            "nodes": [
                {
                    "id": "train_dataloader",
                    "type": "dataLoader",
                    "parameters": {
                        "format": "pt",
                        "batch_size": 128,
                        "dataset_path": dataset_path,
                    },
                },
                {"id": "forward", "type": "forwardPass", "parameters": {}},
                {"id": "loss", "type": "mseCountLoss", "parameters": {}},
                {"id": "optim", "type": "adamOptimiser", "parameters": {}},
            ],
            "edges": [],
        }
    }


def _generate_with_pt_loader(spec: str, dataset_file: Path, tmp_path: Path):
    return client.post(
        "/api/notebook/generate-v2",
        json={
            "spec": spec,
            "pipeline_config": {"framework": "snntorch_sim"},
            "pipeline_phases": _pt_loader_phases(str(dataset_file)),
        },
    )


def _braille_nir_graph() -> nir.NIRGraph:
    """Minimal Braille RNN graph: Input → Linear → RSynaptic → Linear → Synaptic → Output.

    threshold is set to a non-default value (2.0) on purpose so tests can
    distinguish "the threshold kwarg is actually emitted" from "the omitted
    kwarg happens to fall back to a snnTorch default that looks the same".
    """
    w1 = np.zeros((16, 12), dtype=np.float32)
    w2 = np.zeros((7, 16), dtype=np.float32)
    return make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([12])}),
            "fc1": nir.Linear(weight=w1),
            "rsyn": CnlRSynaptic(
                n_neurons=16,
                alpha=0.9,
                beta=0.8,
                threshold=2.0,
                reset_mechanism="subtract",
            ),
            "fc2": nir.Linear(weight=w2),
            "syn": CnlSynaptic(
                n_neurons=7,
                alpha=0.9,
                beta=0.8,
                threshold=2.0,
                reset_mechanism="subtract",
            ),
            "output": nir.Output(output_type={"output": np.array([7])}),
        },
        edges=[
            ("input", "fc1"),
            ("fc1", "rsyn"),
            ("rsyn", "fc2"),
            ("fc2", "syn"),
            ("syn", "output"),
        ],
    )
