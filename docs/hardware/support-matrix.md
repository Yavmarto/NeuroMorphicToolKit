# NIR Round-Trip Fidelity Leaderboard

**Status:** draft — N-MNIST scenario complete with measured accuracy; SHD scenario has structural ratings only, accuracy pending a completed training run.

This page is the public answer to one question: *if I compile a model to NIR (Neuromorphic Intermediate Representation) and run it on target X, what actually survives the round trip?* Every rating below is derived from committed, versioned code and — where marked — measured accuracy artifacts. Nothing here is a vendor claim; it is what NMTK's own converters and simulators do today.

Reproduce everything on this page:

```bash
python3 benchmarks/nir_fidelity/build_shd_fixture.py
python3 benchmarks/nir_fidelity/leaderboard.py
```

The script prints the exact `nir` / `torch` / `snntorch` versions it ran with, so a divergent result is a real regression, not an environment mismatch.

## Fidelity terms

| Term | Meaning |
|---|---|
| `faithful` | The target executes the primitive with semantics indistinguishable from the NIR specification's intent (normal floating-point tolerance). |
| `approximate` | The target executes the primitive, but with a documented semantic gap — quantization, a dropped parameter, or a model simplification. Usable, not spec-accurate. |
| `unsupported` | The target cannot execute the primitive. NMTK rejects the graph before dispatch with a structured diagnostic, rather than silently degrading or crashing mid-run. |

These three terms are the same scale `neurocnl` has used internally since its per-primitive verdict table was built (`neurocnl/neurocnl/runtime/nir_support.py`, tested by `test_nir_support_verdict_matrix.py`). This page is that table applied to two fixed, reproducible benchmark scenarios instead of the abstract primitive list — see [neurocnl's full primitive-level matrix](../../neurocnl/docs/support_matrix.md) for every backend and every NIR node type, including targets not exercised by either scenario below.

## Benchmark set

| Scenario | Graph | Nodes exercised | Demo guide |
|---|---|---|---|
| **N-MNIST** | [`paper/02_cnn/cnn_sinabs.nir`](../../paper/02_cnn/cnn_sinabs.nir) | `Input, Conv2d, IF, SumPool2d, Affine, Flatten, Output` | [GUIDE-nmnist-snntorch.md](../guides/GUIDE-nmnist-snntorch.md) |
| **SHD** | [`benchmarks/nir_fidelity/shd_ff_lif.nir`](../../benchmarks/nir_fidelity/shd_ff_lif.nir) | `Input, Linear, LIF, Output` | [GUIDE-shd-akida.md](../guides/GUIDE-shd-akida.md) |

Both are intentionally small and fixed so every target below is being asked to reproduce the *same* model, not a target-favorable variant.

## N-MNIST — per-target leaderboard

Structural rating from `classify_nir_graph()` against every NMTK target, plus measured cross-framework test accuracy where an artifact exists. The accuracy comparison reuses the original NIR-paper reproduction already committed at `paper/02_cnn/` — same trained weights (`weights.npz`), same graph, evaluated per-framework and stored as `{platform}_accuracy.npy`. Oracle = Sinabs, the framework the graph was exported from.

| Target | Rating | Measured accuracy | Delta vs. oracle | Failure mode |
|---|---|---|---|---|
| Sinabs (oracle) | faithful | 98.47% | +0.00 pp | — |
| snnTorch (`snntorch_sim`) | faithful | 97.85% | −0.62 pp | — |
| Lava | unsupported (NMTK) | 98.15% | −0.32 pp | External Lava run used **lava-dl netx**; NMTK's `lava_sim`/`lava` targets use lower-level **lava-nc**, which has no `Affine`/`Conv2d`/`Flatten` process — see [Promotability](../../neurocnl/docs/support_matrix.md#promotability) |
| Nengo | unsupported (NMTK) | 98.11% | −0.36 pp | External Nengo run predates NMTK's `nengo` converter's `Conv2d` gap; NMTK rejects this graph today |
| Norse | not an NMTK target | 98.11% | −0.36 pp | Reference-only; Norse is not one of NMTK's converters |
| Spyx | not an NMTK target | 97.12% | −1.35 pp | Reference-only; Spyx is not one of NMTK's converters |
| Speck (physical chip) | not an NMTK target | 95.40% | −3.07 pp | Reference-only; largest accuracy loss in the set, consistent with on-chip int8 quantization |
| Brian2 (Speck-equivalent sim) | unsupported | 98.20% | −0.27 pp | External run used a different, hand-tuned Brian2 model; NMTK's `brian2` converter rejects `nir.Affine` outright |
| All other NMTK targets (`akida`, `pynn`, `rockpool`, `sinabs`, `sc_neurocore_*`) | unsupported | pending | pending | Each rejects at the first `Conv2d` or `Affine` node before dispatch — see script output for the exact node per target |

**Reading this table:** the "measured accuracy" column is real, reproducible data for the seven frameworks the original NIR-paper reproduction covered. It is *not* proof that NMTK's own converters can run this graph — five of NMTK's eight non-snnTorch targets structurally reject it today (CNN topologies need `Conv2d`/`Affine`, which most targets don't implement). Where an external framework's number is listed next to an NMTK target rated `unsupported`, that number describes the *external* tool, run outside NMTK, not what NMTK's converter for that target actually does — the note explains the gap.

## SHD — per-target leaderboard

Structural rating only; this fixture is untrained (random weights), so it exists to classify support, not to produce accuracy numbers.

| Target | Rating | Failure mode |
|---|---|---|
| `snntorch_sim` | faithful | — |
| `lava_sim` | faithful | — |
| `sc_neurocore_sim` / `sc_neurocore_fpga` | faithful | — |
| `lava`, `nengo`, `nengo_sim`, `pynn`, `rockpool`, `sinabs`, `sinabs_sim`, `brian2`, `brian2_sim` | approximate | `nir.LIF` executes but with timestep-quantized or reparametrized dynamics — see script output for the exact wording per target |
| `akida` | unsupported | Standalone `nir.LIF` nodes are never emitted by the Akida converter; LIF is only fused into a preceding `Conv2d`/`Linear`, so a bare feedforward LIF chain is dropped entirely, not degraded |

**Measured accuracy — pending.** The only trained SHD numbers on record are from the separate *recurrent* golden path (`neurocli/golden_paths/shd_rnn_snntorch.nmtk`, `cnl.RSynaptic`, not the feedforward graph rated above): **~10% after 50 epochs on the dev rig, versus the ~80–83% Cramer et al. RSNN baseline** — see [CEL-264](../../current%20tasks/2026-09-15/CEL-264-shd-recurrent-scoping.md). The Akida-deployable feedforward variant (this fixture's topology) has a software-simulator export path that works mechanically, but no completed training run has produced a real accuracy number yet — see the open item in [GUIDE-shd-akida.md](../guides/GUIDE-shd-akida.md)'s verification log. This page will be updated with real numbers once that run completes; until then the accuracy cell reads **pending**, not an estimate.

## What would change these ratings

- **Lava:** adding lava-dl netx integration to `lava_sim` would promote `Affine`/`Conv2d`/`Flatten` from `unsupported` to `exact` — tracked in neurocnl's [Promotability](../../neurocnl/docs/support_matrix.md#promotability) note.
- **Akida / SHD:** promoting `nir.LIF` from `unsupported` to `approximate` for the `akida` target (to match what `nir_to_akida` actually does when LIF is fused with an adjacent Linear/Conv) is a small, already-proposed fix — see [CEL-266](../../current%20tasks/2026-09-15/CEL-266-dvs-gesture-akida-lif-spike-findings.md).
- **SHD accuracy:** completing either the recurrent golden-path training run or the Akida feedforward training run on a reachable dev rig closes the "pending" cells above.

## Reproducing this page

```bash
# 1. Regenerate the SHD fixture (deterministic — same seed every time)
python3 benchmarks/nir_fidelity/build_shd_fixture.py

# 2. Print the full leaderboard (structural + measured accuracy)
python3 benchmarks/nir_fidelity/leaderboard.py
```

No dataset download or training run is required to reproduce the structural ratings or the N-MNIST accuracy table — both are computed from artifacts already committed to this repository. See [`benchmarks/nir_fidelity/`](../../benchmarks/nir_fidelity/) for the fixture-generation and leaderboard scripts, and `paper/02_cnn/` for the original per-framework N-MNIST reproduction (weights, notebooks, and raw `*_accuracy.npy` files).
