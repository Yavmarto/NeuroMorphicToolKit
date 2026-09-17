# NIR round-trip fidelity benchmarks (CEL-336)

Scripts and fixtures behind the public leaderboard at
[`docs/hardware/support-matrix.md`](../../docs/hardware/support-matrix.md).

| File | Purpose |
|---|---|
| `build_shd_fixture.py` | Deterministically builds `shd_ff_lif.nir` (the SHD feedforward-LIF structural fixture used by the leaderboard). Untrained — random weights, fixed seed. |
| `shd_ff_lif.nir` | Committed output of the above; do not hand-edit, regenerate instead. |
| `leaderboard.py` | Loads both benchmark graphs (`shd_ff_lif.nir` here, `paper/02_cnn/cnn_sinabs.nir` for N-MNIST), classifies each against every NMTK target via `neurocnl.runtime.nir_support.classify_nir_graph`, and prints the full leaderboard as Markdown. For N-MNIST it also reads the already-committed `paper/02_cnn/*_accuracy.npy` files for measured cross-framework accuracy. |

Run:

```bash
python3 benchmarks/nir_fidelity/build_shd_fixture.py
python3 benchmarks/nir_fidelity/leaderboard.py
```

Requires `nir`, `numpy`, and a `neurocnl` checkout on the path (the script inserts `../../neurocnl` itself). `torch`/`snntorch` are optional — only used to print their versions in the header. The script prints the exact versions it ran with; if you get different ratings than the published page, diff versions first.

No dataset download or training run is needed — every rating and every N-MNIST accuracy number comes from artifacts already committed to this repository. SHD accuracy is not yet measured; see the leaderboard page for what's blocking it.
