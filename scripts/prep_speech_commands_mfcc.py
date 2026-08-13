#!/usr/bin/env python3
"""prep_speech_commands_mfcc.py — one-time offline MFCC preprocessing.

Downloads Google Speech Commands v0.02 (torchaudio.datasets.SPEECHCOMMANDS),
extracts a 20-bin MFCC feature vector per clip (shape: 20 coefficients,
mean-pooled over time → flat vector), stacks all clips into a single
TensorDataset, and saves it to a .pt file that the Train canvas can load
directly with:

    dataLoader → Format = pt
                 Dataset Path = <absolute path to the .pt file>

Usage
-----
    python scripts/prep_speech_commands_mfcc.py [--out PATH] [--n-mfcc N] [--sr SR]

The default output path is:
    data/speech_commands_mfcc20.pt

After running, copy or mount that file into the path that the backend
container can reach (e.g. inside the suite_api_data Docker volume, or on
the remote machine at moosebun2@192.168.2.90).

This script must be run ONCE, outside the app, before the Train canvas demo.
There is no in-app shortcut for this step — say so on camera.

Requirements
------------
    pip install torch torchaudio

Notes
-----
- Speech Commands v0.02 is ~2.3 GB.  The download is resumed automatically
  by torchaudio if the archive already exists in --download-dir.
- All 35 word classes are retained (matching the network's output size of 35).
- MFCC parameters: sample_rate=16000, n_mfcc=20, n_fft=512, hop_length=160
  (10 ms), win_length=400 (25 ms) — matches the standard NeuroBench KWS setup.
- The saved TensorDataset has:
    tensors[0]  features  float32  (N, 20)   ← mean-pooled MFCC, no time axis
    tensors[1]  labels    int64    (N,)
  The neurocnl dataset_loader promotes (N, F) → (N, 1, F) automatically.
"""

from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("prep_speech_commands")


# ── CLI ────────────────────────────────────────────────────────────────────────


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract 20-bin MFCC features from Google Speech Commands and save as .pt",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("data/speech_commands_mfcc20.pt"),
        help="Output .pt file path (absolute or relative to cwd).",
    )
    parser.add_argument(
        "--download-dir",
        type=Path,
        default=Path("data/speech_commands_raw"),
        help="Directory where torchaudio downloads/caches the raw dataset.",
    )
    parser.add_argument(
        "--n-mfcc",
        type=int,
        default=20,
        help="Number of MFCC coefficients to extract.",
    )
    parser.add_argument(
        "--sr",
        type=int,
        default=16000,
        help="Expected sample rate of the audio clips (Hz).",
    )
    parser.add_argument(
        "--splits",
        nargs="+",
        choices=["training", "validation", "testing"],
        default=["training", "validation", "testing"],
        help="Which splits to include in the output tensor.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Process only the first 200 clips per split (smoke-test).",
    )
    return parser.parse_args()


# ── Label catalogue ────────────────────────────────────────────────────────────

# Speech Commands v0.02 canonical 35-word list (alphabetical order).
# The integer index is the class label written into the .pt file.
CLASSES: list[str] = [
    "backward", "bed", "bird", "cat", "dog",
    "down", "eight", "five", "follow", "forward",
    "four", "go", "happy", "house", "learn",
    "left", "marvin", "nine", "no", "off",
    "on", "one", "right", "seven", "sheila",
    "six", "stop", "three", "tree", "two",
    "up", "visual", "wow", "yes", "zero",
]
LABEL_MAP: dict[str, int] = {word: idx for idx, word in enumerate(CLASSES)}


# ── Core preprocessing ─────────────────────────────────────────────────────────


def _extract_mfcc_features(
    waveform,   # torch.Tensor shape (1, num_samples)
    sample_rate: int,
    transform,  # torchaudio.transforms.MFCC
    expected_sr: int,
) -> "torch.Tensor":  # noqa: F821 — torch imported at runtime
    """Return a 1-D mean-pooled MFCC feature vector of shape (n_mfcc,)."""
    import torch
    import torchaudio

    if sample_rate != expected_sr:
        waveform = torchaudio.functional.resample(waveform, sample_rate, expected_sr)

    # Pad or truncate to exactly 1 second (16 000 samples).
    target_len = expected_sr
    current_len = waveform.shape[-1]
    if current_len < target_len:
        pad = target_len - current_len
        waveform = torch.nn.functional.pad(waveform, (0, pad))
    elif current_len > target_len:
        waveform = waveform[..., :target_len]

    # MFCC: (1, n_mfcc, T_frames)
    mfcc = transform(waveform)          # (1, n_mfcc, T)
    mfcc = mfcc.squeeze(0)             # (n_mfcc, T)
    features = mfcc.mean(dim=-1)       # (n_mfcc,)  — mean-pool over time
    return features


def _patch_torchaudio_load() -> None:
    """Route torchaudio.load through soundfile instead of TorchCodec.

    Newer torchaudio hardcodes TorchCodec (which needs a system ffmpeg) for
    `load()`, ignoring the `backend=` kwarg entirely. Speech Commands clips
    are plain 16-bit PCM WAV, so soundfile alone decodes them fine and avoids
    the extra native dependency. `torchaudio.datasets.utils._load_waveform`
    looks up `torchaudio.load` at call time, so reassigning it here redirects
    every dataset read without touching torchaudio internals.
    """
    import torch
    import torchaudio

    try:
        import soundfile as sf
    except ImportError:
        log.error("soundfile is not installed.  Run: pip install soundfile")
        sys.exit(1)

    def _load(
        uri,
        frame_offset: int = 0,
        num_frames: int = -1,
        normalize: bool = True,
        channels_first: bool = True,
        format=None,
        buffer_size: int = 4096,
        backend=None,
    ):
        data, sample_rate = sf.read(uri, dtype="float32", always_2d=True)
        waveform = torch.from_numpy(data.T)  # (channel, time)
        if frame_offset or num_frames != -1:
            end = None if num_frames == -1 else frame_offset + num_frames
            waveform = waveform[:, frame_offset:end]
        if not channels_first:
            waveform = waveform.T
        return waveform, sample_rate

    torchaudio.load = _load


def _build_transform(n_mfcc: int, sr: int):
    """Construct the torchaudio MFCC transform once and reuse it."""
    try:
        import torchaudio
    except ImportError:
        log.error("torchaudio is not installed.  Run: pip install torchaudio")
        sys.exit(1)
    return torchaudio.transforms.MFCC(
        sample_rate=sr,
        n_mfcc=n_mfcc,
        melkwargs={
            "n_fft": 512,
            "hop_length": 160,   # 10 ms at 16 kHz
            "win_length": 400,   # 25 ms at 16 kHz
            "n_mels": 40,
        },
    )


def _process_split(
    split: str,
    download_dir: Path,
    transform,
    expected_sr: int,
    dry_run: bool,
) -> "tuple[list, list]":  # (feature_tensors, labels)
    try:
        import torchaudio
    except ImportError:
        log.error("torchaudio is not installed.  Run: pip install torchaudio")
        sys.exit(1)

    log.info("Loading split '%s' from %s …", split, download_dir)
    dataset = torchaudio.datasets.SPEECHCOMMANDS(
        root=str(download_dir),
        download=True,
        subset=split,
    )

    features_list: list = []
    labels_list: list = []
    skipped = 0
    limit = 200 if dry_run else None
    t0 = time.monotonic()

    for i, item in enumerate(dataset):
        if limit is not None and i >= limit:
            break

        # torchaudio.datasets.SPEECHCOMMANDS yields:
        #   (waveform, sample_rate, label_str, speaker_id, utterance_number)
        waveform, sr, label_str, *_ = item

        if label_str not in LABEL_MAP:
            # Treat as unknown / background — skip (there are no unknown clips
            # in v0.02's subset; all clips have a canonical label).
            skipped += 1
            continue

        feat = _extract_mfcc_features(waveform, sr, transform, expected_sr)
        features_list.append(feat)
        labels_list.append(LABEL_MAP[label_str])

        if (i + 1) % 2000 == 0:
            elapsed = time.monotonic() - t0
            rate = (i + 1) / elapsed
            log.info(
                "  %s: %d / %s clips  (%.0f clips/s)",
                split,
                i + 1,
                "~200 (dry-run)" if dry_run else len(dataset),
                rate,
            )

    elapsed = time.monotonic() - t0
    log.info(
        "Split '%s' done: %d clips extracted, %d skipped  (%.1f s)",
        split, len(features_list), skipped, elapsed,
    )
    return features_list, labels_list


# ── Main ───────────────────────────────────────────────────────────────────────


def main() -> None:
    args = _parse_args()

    try:
        import torch
    except ImportError:
        log.error("PyTorch is not installed.  Run: pip install torch torchaudio")
        sys.exit(1)

    _patch_torchaudio_load()

    out_path: Path = args.out.resolve()
    download_dir: Path = args.download_dir.resolve()
    download_dir.mkdir(parents=True, exist_ok=True)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if out_path.exists():
        log.warning(
            "Output file already exists: %s\n"
            "Delete it first if you want to re-generate.",
            out_path,
        )
        sys.exit(0)

    log.info("=" * 60)
    log.info("Speech Commands MFCC preprocessing")
    log.info("  n_mfcc     : %d", args.n_mfcc)
    log.info("  sample_rate: %d Hz", args.sr)
    log.info("  splits     : %s", args.splits)
    log.info("  output     : %s", out_path)
    log.info("  dry-run    : %s", args.dry_run)
    log.info("=" * 60)

    transform = _build_transform(args.n_mfcc, args.sr)

    all_features: list = []
    all_labels: list = []

    for split in args.splits:
        feats, labels = _process_split(
            split=split,
            download_dir=download_dir,
            transform=transform,
            expected_sr=args.sr,
            dry_run=args.dry_run,
        )
        all_features.extend(feats)
        all_labels.extend(labels)

    log.info("Stacking %d feature tensors …", len(all_features))
    features_tensor = torch.stack(all_features)   # (N, n_mfcc)  float32
    labels_tensor   = torch.tensor(all_labels, dtype=torch.long)  # (N,)

    log.info(
        "Tensor shapes: features=%s  labels=%s  classes=%d",
        tuple(features_tensor.shape),
        tuple(labels_tensor.shape),
        len(CLASSES),
    )

    dataset = torch.utils.data.TensorDataset(features_tensor, labels_tensor)

    log.info("Saving to %s …", out_path)
    torch.save(dataset, out_path)
    size_mb = out_path.stat().st_size / 1024 / 1024
    log.info("Done.  File size: %.1f MB", size_mb)

    log.info("")
    log.info("Next step — Train canvas:")
    log.info("  dataLoader → Format = pt")
    log.info("  dataLoader → Dataset Path = %s", out_path)
    log.info("  (copy/mount this file into the backend container's data volume")
    log.info("   if the backend is running in Docker on a remote host)")


if __name__ == "__main__":
    main()
