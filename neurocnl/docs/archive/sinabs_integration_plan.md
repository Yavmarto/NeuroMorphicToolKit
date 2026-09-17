# Integration Plan for SynSense `sinabs` in `neurocnl`

## 1. Convert NeuroCNL Graph (via NIR) to `sinabs.network.Network`
- NeuroCNL uses NIR as its internal pivot representation (`nir.NIRGraph`).
- Sinabs models are standard PyTorch modules. Since `sinabs` version 2.0+, it heavily relies on `torch.nn.Sequential` and module lists, and provides wrappers like `sinabs.network.Network`.
- `nirtorch` provides standard conversions from NIR to PyTorch/sinabs. However, for a direct `sinabs_io.py` implementation:
  - We will parse `nir.NIRGraph` into a `torch.nn.Sequential` consisting of `torch.nn.Linear` (or `torch.nn.Conv2d`) interspersed with `sinabs.layers.LIF` or `sinabs.layers.IAF`.
- **Steps to export (NIR → sinabs):**
  - Extract nodes and edges from `nir.NIRGraph`.
  - Since Sinabs relies on PyTorch's sequential or modular layers, we map:
    - `nir.LIF` / `nir.CubaLIF` to `sinabs.layers.LIF`.
    - `nir.IF` to `sinabs.layers.IAF`.
    - `nir.Linear` to `torch.nn.Linear` or `sinabs.layers.Merge`.
    - `nir.Affine` to `torch.nn.Linear` (with bias).
  - Trace the graph topology to construct the sequential execution code and wrap it in `sinabs.network.Network`.

## 2. Convert sinabs model to NeuroCNL representation (sinabs → NIR)
- Since `sinabs` models are standard `torch.nn.Module`, we can iterate over the layers (using `model.children()` or tracing).
- **Steps to extract (sinabs → NIR):**
  - Map `sinabs.layers.IAF` → `nir.IF`.
  - Map `sinabs.layers.LIF` / `sinabs.layers.ExpLeak` → `nir.LIF` or `nir.CubaLIF`.
  - Map `torch.nn.Linear` / `torch.nn.Conv2d` → `nir.Linear` / `nir.Conv2d`.
  - Use PyTorch hooks or symbolic tracing to reconstruct the connectivity graph into `nir.NIRGraph` edges.

## 3. Mapping of sinabs Layer Types to NeuroCNL
| Sinabs Layer | NeuroCNL / NIR Model | Notes |
| --- | --- | --- |
| `sinabs.layers.IAF` | `nir.IF` | Integrate-and-Fire, no leak. |
| `sinabs.layers.LIF` | `nir.LIF` | Leaky Integrate-and-Fire. |
| `sinabs.layers.ExpLeak` | `nir.LI` / `nir.LIF` | Exponential leak dynamics. |
| `torch.nn.Linear` | `nir.Linear` | Synapse / weight mapping. |

## 4. Synapse / Weight Handling
Sinabs natively uses standard PyTorch stateless layers for synapses (e.g., `torch.nn.Linear`, `torch.nn.Conv2d`).
- During `to_nir`: Extract weights using `layer.weight.detach().numpy()` and bias using `layer.bias.detach().numpy()`. These map directly to `nir.Linear` and `nir.Affine`.
- During `from_nir`: Instantiate PyTorch modules initialized with the corresponding Numpy arrays from the NIR graph.

## 5. Location of Converter
- `neurocnl/converter/sinabs_io.py`: Will contain a `SinabsIO` class implementing the `FrameworkIO` protocol (`to_nir` and `from_nir`), mirroring `lava_io.py` and `nengo_io.py`.
- `neurocnl/export/sinabs_exporter.py`: An exporter point if explicit standalone code generation for SynSense deployment pipelines is required.
- `neurocnl/backends/sinabs_capabilities.py`: A capabilities profile establishing feature support (like quantization handling mapping for Speck/DYNAP-CNN).

## 6. Dependency Declaration
- Will be added to `pyproject.toml` under `[project.optional-dependencies]`:
  ```toml
  synsense = ["sinabs>=2.0.0", "torch>=1.8.0"]
  ```

## 7. CPU-only Test Stub Outline
- The test stub will run entirely on the host CPU using standard PyTorch (no DYNAP-CNN required).
- Reside in `tests/test_sinabs_io.py` or `neurocnl/export/test_exporters.py`.
- **Test 1:** Instantiate a simple NIR graph (1 Linear node connected to 1 LIF node). Convert it to sinabs via `SinabsIO.from_nir`. Assert the resulting PyTorch module contains a `torch.nn.Linear` followed by a `sinabs.layers.LIF`.
- **Test 2:** Build a simple sinabs sequential model (`nn.Sequential(nn.Linear(2, 2), sinabs.layers.LIF(tau_mem=10.0))`). Convert to NIR via `SinabsIO.to_nir`. Assert the resulting graph nodes correctly represent `nir.Linear` and `nir.LIF`.
