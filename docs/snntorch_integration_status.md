# snnTorch Integration Status in NeuroMorphicToolKit

After auditing the actual Python and Dart source code (excluding documentation), here are the corrected findings regarding `snnTorch` integration:

## 1. Where is `snntorch` support implemented?
**It is not currently implemented in the codebase.** 

While the architecture documentation (`docs/unified_toolkit_architecture.md`) heavily describes an `snnTorchBackend` and an integration pipeline, a search across all functional code (including `Neurochip`, `Neurosim`, and the backend APIs) reveals **zero** actual implementation of these concepts. 

The only functional reference to `snnTorch` in the entire source tree is a single check in `scripts/backend_endpoint_smoke.py` that simply tests if the module can be imported (`import snntorch`). The `SNNTorchWrapper` and `snnTorchBackend` classes described in the docs do not exist in the code.

- **Neurosim** *does* successfully implement the translation from visual design/CNL into the intermediate `NIR` format (in `neurosim/app/routers/export.py`).
- **Neurochip**, however, currently lacks the implementation to hand off that `NIR` artifact to `snnTorch`.

## 2. How far along is the end-to-end `CNL -> NIR -> snnTorch` simulation?
It is **incomplete and currently blocked** at the NIR export stage.

- **`CNL -> NIR`:** ✅ **Done.** `Neurosim` successfully exports Canvas designs to valid `nir.NIRGraph` representations.
- **`NIR -> snnTorch import`:** ❌ **Not Implemented.** Despite the architecture docs stating "Done", there is no code in the backend actually calling `snntorch.import_nir`.
- **End-to-End Simulation (`CNL -> NIR -> snnTorch -> Training`)**: ❌ **Not Implemented.** No training loop or benchmark execution exists for `snnTorch`.
- **Cross-platform validation:** ❌ **Not Implemented.**

## 3. What will the end product look like (according to the design)?
The final product is *designed* to provide a **"Research-to-Production Pipeline"**, though this remains theoretical until the backend is built:

1. **Design:** Network design via UI or CNL.
2. **Translation:** Automatic export to the universal `NIR` format.
3. **Training & Simulation:** The backend is *intended* to invoke `snnTorch`, load the `NIR` graph, wrap it as a PyTorch Module, and use surrogate gradients to train the SNN.
4. **Hardware Deployment:** The same trained `NIR` model is meant to be deployed to edge hardware targets (Intel Loihi 2, BrainChip Akida, Xylo) with a target accuracy drop of **less than 5%**.