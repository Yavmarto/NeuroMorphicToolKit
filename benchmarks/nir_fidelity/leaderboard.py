"""NIR round-trip fidelity leaderboard (CEL-336).

Reproducibly builds the public per-target fidelity leaderboard from two
fixed scenarios:

    N-MNIST  paper/02_cnn/cnn_sinabs.nir   (Conv2d/IF/SumPool2d/Affine CNN)
    SHD      benchmarks/nir_fidelity/shd_ff_lif.nir (Linear/LIF feedforward)

For each scenario this script:

1. Loads the committed .nir graph.
2. Runs neurocnl.runtime.nir_support.classify_nir_graph() against every
   NMTK backend to get a structural verdict (exact / approximate /
   unsupported) and the failure-mode diagnostics — this needs no training
   run and is fully reproducible from committed code.
3. For N-MNIST only, also reads the already-committed cross-framework
   accuracy artifacts under paper/02_cnn/ (*_accuracy.npy) and reports the
   measured accuracy delta against the Sinabs oracle (the framework the
   .nir graph was exported from).

Where no accuracy artifact exists yet (every SHD target, and any N-MNIST
target without an *_accuracy.npy file), the leaderboard prints "pending" —
never a fabricated number.

Run:
    python3 benchmarks/nir_fidelity/build_shd_fixture.py   # once, regenerates the fixture
    python3 benchmarks/nir_fidelity/leaderboard.py
"""

from __future__ import annotations

import os
import sys

import nir
import numpy as np

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(_REPO_ROOT, "neurocnl"))

from neurocnl.runtime.nir_support import classify_nir_graph, list_supported_backends  # noqa: E402

NMNIST_NIR = os.path.join(_REPO_ROOT, "paper", "02_cnn", "cnn_sinabs.nir")
SHD_NIR = os.path.join(os.path.dirname(__file__), "shd_ff_lif.nir")

# platform label -> accuracy .npy file under paper/02_cnn/
NMNIST_ACCURACY_FILES = {
    "Sinabs (oracle — export source)": "sinabs_accuracy.npy",
    "snnTorch": "snntorch_accuracy.npy",
    "Lava": "lava_accuracy.npy",
    "Nengo": "nengo_accuracy.npy",
    "Norse": "norse_accuracy.npy",
    "Spyx": "spyx_accuracy.npy",
    "Speck (chip)": "speck_accuracy.npy",
    "Brian2 (Speck-equivalent sim)": "s2_brian2_accuracy.npy",
}


def print_versions() -> None:
    print(f"python {sys.version.split()[0]}")
    print(f"nir {nir.__version__}")
    try:
        import torch

        print(f"torch {torch.__version__}")
    except ImportError:
        pass
    try:
        import snntorch

        print(f"snntorch {snntorch.__version__}")
    except ImportError:
        pass
    print()


def structural_leaderboard(name: str, nir_path: str) -> None:
    graph = nir.read(nir_path)
    print(f"## {name} — structural fidelity ({os.path.relpath(nir_path, _REPO_ROOT)})")
    print()
    print("| NMTK target | rating | failure mode |")
    print("|---|---|---|")
    for backend in sorted(list_supported_backends()):
        result = classify_nir_graph(graph, backend)
        rating = {"exact": "faithful", "approximate": "approximate", "unsupported": "unsupported"}[
            result.level
        ]
        if result.level == "exact":
            failure_mode = "—"
        else:
            # diagnostics is sorted by node type name, not by severity — pick
            # the message that actually explains the overall verdict rather
            # than whichever node type happens to sort first.
            worst_nodes = result.unsupported_nodes or result.approximate_nodes
            failure_mode = next(
                (d for d in result.diagnostics if any(f"nir.{n} " in d for n in worst_nodes)),
                result.diagnostics[0] if result.diagnostics else "n/a",
            )
        print(f"| `{backend}` | {rating} | {failure_mode} |")
    print()


def nmnist_accuracy_table() -> None:
    print("## N-MNIST — measured cross-framework accuracy")
    print()
    print(
        "Same trained weights (`weights.npz`), same `cnn_sinabs.nir` graph, "
        "evaluated per-framework by `paper/02_cnn/*_apply.ipynb` / "
        "`speck_accuracy.py` and stored as `{platform}_accuracy.npy`. "
        "Oracle = Sinabs (the framework the NIR graph was exported from)."
    )
    print()
    print("| Platform | Test accuracy | Delta vs. Sinabs oracle |")
    print("|---|---|---|")
    oracle_path = os.path.join(_REPO_ROOT, "paper", "02_cnn", NMNIST_ACCURACY_FILES["Sinabs (oracle — export source)"])
    oracle_acc = float(np.load(oracle_path))
    for label, filename in NMNIST_ACCURACY_FILES.items():
        path = os.path.join(_REPO_ROOT, "paper", "02_cnn", filename)
        if not os.path.exists(path):
            print(f"| {label} | pending | pending |")
            continue
        acc = float(np.load(path))
        delta = (acc - oracle_acc) * 100.0
        sign = "+" if delta >= 0 else ""
        print(f"| {label} | {acc * 100:.2f}% | {sign}{delta:.2f} pp |")
    print()


def shd_accuracy_note() -> None:
    print("## SHD — measured accuracy")
    print()
    print(
        "No committed accuracy artifact exists yet for this fixture. The only "
        "measured SHD numbers on record are from the separate recurrent golden "
        "path (`neurocli/golden_paths/shd_rnn_snntorch.nmtk`, `cnl.RSynaptic`, "
        "not the feedforward graph classified above): **~10% after 50 epochs "
        "on the dev rig, vs. the ~80–83% Cramer et al. RSNN baseline** "
        "(see `docs/guides/GUIDE-shd-akida.md` and "
        "`current tasks/2026-09-15/CEL-264-shd-recurrent-scoping.md`). "
        "The Akida feedforward variant's software-simulator accuracy and "
        "on-card accuracy are both still **pending** a completed training run "
        "— tracked as the open item in `docs/guides/GUIDE-shd-akida.md`'s "
        "verification log."
    )
    print()


if __name__ == "__main__":
    print_versions()
    structural_leaderboard("N-MNIST (CNN)", NMNIST_NIR)
    nmnist_accuracy_table()
    structural_leaderboard("SHD (feedforward LIF)", SHD_NIR)
    shd_accuracy_note()
