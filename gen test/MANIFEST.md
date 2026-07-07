# gen test — generation manifest

| Notebook | Framework | Support level | Status | Detail |
|---|---|---|---|---|
| lif_norse | snntorch_sim | exact | OK | 9 cells, artifacts: ['weights.npz'] |
| lif_rockpool | snntorch_sim | exact | OK | 9 cells, artifacts: ['weights.npz'] |
| lif_nengo | nengo | approximate | OK | 10 cells |
| lif_sinabs | sinabs | approximate | OK | 10 cells |
| lif_snntorch | snntorch_sim | exact | OK | 9 cells, artifacts: ['weights.npz'] |
| snntorch_apply | snntorch_sim | unsupported | OK | 10 cells, artifacts: ['weights.npz'] |
| Braille_training_snntorch | snntorch_sim | approximate | OK | 10 cells, artifacts: ['weights.npz'] |
| snntorch_apply_subtract | snntorch_sim | approximate | OK | 10 cells, artifacts: ['weights.npz'] |
| snntorch_apply_zero | snntorch_sim | approximate | OK | 10 cells, artifacts: ['weights.npz'] |

## Findings

- **`snntorch_apply` is actually `unsupported`, not the 🟢 HIGH the companion doc claims.** `classify_nir_graph` reports: `"snnTorch simulator: nir.SumPool2d is not supported and cannot be executed."` Direct inspection of `paper/02_cnn/cnn_sinabs.nir` shows its real pooling nodes are `nir.SumPool2d`, not the `AvgPool2d(2×2)` the companion doc's architecture diagram describes — and `SumPool2d` is explicitly in `nir_support.py`'s `"unsupported"` list for `snntorch_sim`. The generated notebook still contains a working `SumPool2d` PyTorch implementation (codegen degrades gracefully), but CNLStudio's own simulator would flag/block this run. This is a real correction to `cnlstudio_notebook_analysis.md`'s Notebook 2 verdict, found only by actually generating and classifying the real file — not something the written UI guide could have caught.
- **The 3 Braille notebooks correctly classify as `approximate`, not `exact`, despite `Synaptic`/`RSynaptic` being listed `"exact"` for `snntorch_sim`.** This is expected, not a bug: the real `.nir` files already have `cnl.RSynaptic`/`cnl.Synaptic` flattened down to raw `nir.CubaLIF` + `nir.Linear` at export time (confirmed by dumping node types), and `CubaLIF` is `"approximate"` for `snntorch_sim`. The generated code embeds this as `snn.Leaky` with a code comment noting synaptic current filtering isn't modelled — numerically close but not an exact reproduction of the original `snn.RSynaptic`/`snn.Synaptic` dynamics.
- All 9 notebooks generated without exceptions and validated as well-formed notebook JSON (`nbformat=4`, non-empty `cells`). Spot-checked expected node types/imports in each (`Conv2d`/`SumPool2d` in the CNN one, `nengo` in the Nengo one, `sinabs`/`sl.` in the Sinabs one, `snn.Leaky` in the LIF/Braille ones).
