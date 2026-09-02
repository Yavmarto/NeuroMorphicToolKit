#!/usr/bin/env python3
"""normalize_mfcc_features.py — one-time z-score normalization pass.

The raw MFCC features produced by prep_speech_commands_mfcc.py have wildly
different per-coefficient scales (coefficient 0 alone averages ~-174 with a
std of ~56, range -392..122). The keyword_spotting.cnl spec wires this raw
input directly into a LIF neuron with threshold=1.0 and no learnable layer
in front of it, so that scale mismatch either saturates or kills the first
spiking layer regardless of what the network learns downstream.

This script computes per-coefficient mean/std from the TRAINING split only,
then applies (x - mean) / std to both the train and test tensors (test
always uses the train-derived stats, never its own — avoids leaking test
statistics into normalization). Output files keep the same
TensorDataset(features, labels) shape the existing notebook loader code
already expects, so no codegen changes are needed — just repoint the
Train/Eval canvases' Dataset Path fields at the new files.

Usage
-----
    python3 scripts/normalize_mfcc_features.py \\
        --train data/speech_commands_mfcc20_train.pt \\
        --test  data/speech_commands_mfcc20_test.pt
"""

from __future__ import annotations

import argparse
import logging
from pathlib import Path

import torch
from torch.serialization import safe_globals
from torch.utils.data import TensorDataset

logging.basicConfig(level=logging.INFO, format="%(message)s")
log = logging.getLogger("normalize_mfcc")


def _load(path: Path) -> tuple[torch.Tensor, torch.Tensor]:
    with safe_globals([TensorDataset]):
        ds = torch.load(path, weights_only=True)
    return ds.tensors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--train", type=Path, default=Path("data/speech_commands_mfcc20_train.pt"))
    parser.add_argument("--test", type=Path, default=Path("data/speech_commands_mfcc20_test.pt"))
    parser.add_argument(
        "--suffix",
        default="_norm",
        help="Appended to each input filename's stem for the output file.",
    )
    args = parser.parse_args()

    train_features, train_labels = _load(args.train)
    test_features, test_labels = _load(args.test)

    mean = train_features.mean(dim=0)
    std = train_features.std(dim=0).clamp_min(1e-6)  # guard against a zero-variance coefficient

    log.info("Per-coefficient mean (first 5): %s", mean[:5].tolist())
    log.info("Per-coefficient std  (first 5): %s", std[:5].tolist())

    train_norm = (train_features - mean) / std
    test_norm = (test_features - mean) / std

    train_out = args.train.with_name(args.train.stem + args.suffix + args.train.suffix)
    test_out = args.test.with_name(args.test.stem + args.suffix + args.test.suffix)

    torch.save(TensorDataset(train_norm, train_labels), train_out)
    torch.save(TensorDataset(test_norm, test_labels), test_out)

    log.info("Wrote %s (mean=%.4f, std=%.4f)", train_out, train_norm.mean().item(), train_norm.std().item())
    log.info("Wrote %s (mean=%.4f, std=%.4f)", test_out, test_norm.mean().item(), test_norm.std().item())


if __name__ == "__main__":
    main()
