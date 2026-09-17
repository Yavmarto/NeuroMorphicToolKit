# NMTK demo guides

Reproducible end-to-end walkthroughs for researchers and SDK teams. Each guide lists prerequisites, exact commands, expected output, typical runtime, and known failure modes.

| Guide | Dataset | Target | Hardware |
|---|---|---|---|
| [N-MNIST on snnTorch](./GUIDE-nmnist-snntorch.md) | N-MNIST (neuromorphic vision) | `snntorch_sim` — train, export NIR, evaluate | **works** (simulator only) |
| [SHD on Akida](./GUIDE-shd-akida.md) | SHD (spoken digits) | snnTorch train → Akida export → optional card deploy | Train/export: **works**; card inference: **needs hardware** |

Support labels match the root [README](../../README.md): **works**, **needs hardware**, **not implemented**.
