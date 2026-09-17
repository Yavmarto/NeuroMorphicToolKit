"""Build the committed SHD feedforward-LIF NIR fixture used by leaderboard.py.

Topology matches the "SHD Spoken-Digit Classifier (Akida)" gallery template and
docs/guides/GUIDE-shd-akida.md (the demo-guides scenario CEL-336 reuses):

    Input(700) -> Linear(700,128) -> LIF(128) -> Linear(128,20) -> LIF(20) -> Output(20)

This is a structural fixture (random weights, untrained) — it exists so
classify_nir_graph() can be run against every NMTK backend without requiring a
completed training run. It is NOT the trained SHD checkpoint; accuracy numbers
for SHD come from the separate golden-path training runs cited in
leaderboard.py's SHD section (neurocli/golden_paths/shd_rnn_snntorch.nmtk and
the Akida guide), not from this fixture's weights.

Run:
    python3 benchmarks/nir_fidelity/build_shd_fixture.py
"""

from __future__ import annotations

import os

import nir
import numpy as np

OUT_PATH = os.path.join(os.path.dirname(__file__), "shd_ff_lif.nir")


def build_graph() -> nir.NIRGraph:
    rng = np.random.default_rng(0)
    n_in, n_hidden, n_out = 700, 128, 20

    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([n_in])}),
            "lin1": nir.Linear(
                weight=rng.normal(0, 0.05, (n_hidden, n_in)).astype(np.float32)
            ),
            "lif1": nir.LIF(
                tau=np.full(n_hidden, 0.02, dtype=np.float32),
                r=np.ones(n_hidden, dtype=np.float32),
                v_leak=np.zeros(n_hidden, dtype=np.float32),
                v_threshold=np.full(n_hidden, 0.6, dtype=np.float32),
            ),
            "lin2": nir.Linear(
                weight=rng.normal(0, 0.1, (n_out, n_hidden)).astype(np.float32)
            ),
            "lif2": nir.LIF(
                tau=np.full(n_out, 0.03, dtype=np.float32),
                r=np.ones(n_out, dtype=np.float32),
                v_leak=np.zeros(n_out, dtype=np.float32),
                v_threshold=np.full(n_out, 0.7, dtype=np.float32),
            ),
            "output": nir.Output(output_type={"output": np.array([n_out])}),
        },
        edges=[
            ("input", "lin1"),
            ("lin1", "lif1"),
            ("lif1", "lin2"),
            ("lin2", "lif2"),
            ("lif2", "output"),
        ],
        type_check=False,
    )


if __name__ == "__main__":
    graph = build_graph()
    nir.write(OUT_PATH, graph)
    print(f"wrote {OUT_PATH} ({len(graph.nodes)} nodes)")
