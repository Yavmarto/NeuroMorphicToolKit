# /// script
# requires-python = ">=3.11"
# dependencies = ["torch", "torchvision"]
# ///
"""Export flattened MNIST as .pt TensorDatasets for the NMTK Data Loader.

NMTK's Data Loader has no built-in MNIST option — only tonic (N-MNIST/SHD/
N-TIDIGITS) and `format=pt` (neurocnl/backend/app/routers/notebook.py:2850).
This writes exactly what `_pt_loading_code` expects: a `TensorDataset` that
loads under `weights_only=True` inside `safe_globals([TensorDataset])`.

Shape is (N, 784), not (N, 1, 28, 28), on purpose: the generated feedforward
`forward()` takes its `x.dim() == 2` branch for static features and expands
them to (num_steps, B, 784) — the same image at every timestep, which is
snnTorch Tutorial 5's input scheme (notebook.py:1124).

Run:  uv run "current tasks/2026-07-28/prepare_mnist_pt.py"
"""

import sys
from pathlib import Path

import torch
from torch.utils.data import TensorDataset
from torchvision import datasets, transforms

# ponytail: 9k/1k/2k subset keeps an epoch at ~1-2 min and each upload under
# 30 MB. Raise to 60000/10000 for the headline ~97-98% once the pipeline is
# proven — nothing else changes.
N_TRAIN, N_VAL, N_TEST = 9_000, 1_000, 2_000

OUT_DIR = Path(sys.argv[1] if len(sys.argv) > 1 else "workspaces")
CACHE_DIR = Path(sys.argv[2]) if len(sys.argv) > 2 else OUT_DIR / ".mnist_raw"


def dump(ds, lo: int, hi: int, path: Path) -> None:
    x = torch.stack([ds[i][0].view(-1) for i in range(lo, hi)]).float()
    y = torch.tensor([ds[i][1] for i in range(lo, hi)], dtype=torch.long)
    torch.save(TensorDataset(x, y), path)
    size_mb = path.stat().st_size / 1e6
    print(f"{path}  x={tuple(x.shape)} y={tuple(y.shape)}  {size_mb:.1f} MB")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tf = transforms.ToTensor()  # -> float32 in [0, 1], (1, 28, 28)
    train = datasets.MNIST(CACHE_DIR, train=True, download=True, transform=tf)
    test = datasets.MNIST(CACHE_DIR, train=False, download=True, transform=tf)

    dump(train, 0, N_TRAIN, OUT_DIR / "mnist_train.pt")
    # Validation comes out of the train split, so the test set stays untouched
    # by the Validation Loop's best-checkpoint selection.
    dump(train, N_TRAIN, N_TRAIN + N_VAL, OUT_DIR / "mnist_val.pt")
    dump(test, 0, N_TEST, OUT_DIR / "mnist_test.pt")


if __name__ == "__main__":
    main()
