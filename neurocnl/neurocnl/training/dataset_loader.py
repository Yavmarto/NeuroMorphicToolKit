from __future__ import annotations

import json
import struct
from collections.abc import Mapping
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import IO, Any

import numpy as np

from neurocnl.training.dataset_fixtures import EventDatasetFixture


class DatasetFormat(StrEnum):
    nmnist_bin = "nmnist_bin"
    hdf5_shd = "hdf5_shd"
    hdf5_dvs_gesture = "hdf5_dvs_gesture"
    hdf5_generic_event = "hdf5_generic_event"
    aedat = "aedat"
    aedat4 = "aedat4"
    tonic_nmnist = "tonic_nmnist"
    tonic_shd = "tonic_shd"
    pt = "pt"


@dataclass(frozen=True, slots=True)
class EventSample:
    label: int
    x: np.ndarray[Any, Any]
    y: np.ndarray[Any, Any]
    t: np.ndarray[Any, Any]
    p: np.ndarray[Any, Any]


class DatasetLoadError(ValueError):
    """Raised when a dataset cannot be opened or decoded honestly."""


def load_event_dataset(
    *,
    dataset_name: str,
    dataset_path: str,
    dataset_format: str | None,
    loader_config: Mapping[str, Any] | None = None,
    timesteps: int = 12,
    max_samples: int | None = None,
) -> EventDatasetFixture:
    source = Path(dataset_path).expanduser().resolve()
    if not source.exists():
        raise DatasetLoadError(
            f"Dataset path '{source}' does not exist. Re-download it in Setup and retry."
        )
    resolved_format = _resolve_dataset_format(source, dataset_format)
    config = dict(loader_config or {})
    samples = _load_samples(
        source,
        resolved_format,
        config,
        max_samples=max_samples,
    )
    return _samples_to_fixture(
        dataset_name=dataset_name,
        dataset_path=str(source),
        dataset_format=resolved_format.value,
        samples=samples,
        timesteps=timesteps,
        sensor_width=int(config.get("sensor_width", 0) or 0),
        sensor_height=int(config.get("sensor_height", 0) or 0),
    )


def _resolve_dataset_format(source: Path, declared: str | None) -> DatasetFormat:
    raw = (declared or "").strip().lower()
    if raw:
        try:
            return DatasetFormat(raw)
        except ValueError as exc:
            raise DatasetLoadError(
                f"Unsupported dataset format '{declared}' for '{source.name}'."
            ) from exc
    suffixes = [part.lower() for part in source.suffixes]
    if source.is_dir():
        return DatasetFormat.nmnist_bin
    if ".aedat4" in suffixes:
        return DatasetFormat.aedat4
    if ".aedat" in suffixes or source.suffix.lower() == ".dat":
        return DatasetFormat.aedat
    if source.suffix.lower() in {".h5", ".hdf5"}:
        return DatasetFormat.hdf5_generic_event
    if source.suffix.lower() == ".bin":
        return DatasetFormat.nmnist_bin
    if source.suffix.lower() == ".pt":
        return DatasetFormat.pt
    raise DatasetLoadError(
        f"Could not infer dataset format from '{source.name}'. "
        "Set 'format' in the dataset catalog entry."
    )


_TONIC_DATASET_MAP: dict[DatasetFormat, str] = {
    DatasetFormat.tonic_nmnist: "NMNIST",
    DatasetFormat.tonic_shd: "SHD",
}

_TONIC_FORMATS = frozenset(_TONIC_DATASET_MAP)


def _load_tonic_samples(
    source: Path,
    dataset_format: DatasetFormat,
    loader_config: dict[str, Any],
    *,
    max_samples: int | None,
) -> list[EventSample]:
    """Load a tonic dataset and convert to EventSample list.

    Requires the ``tonic`` package. Raises :class:`DatasetLoadError` with an
    actionable ``pip install tonic`` hint when it is absent.
    """
    try:
        import tonic
        import tonic.transforms as transforms
    except ImportError as exc:
        raise DatasetLoadError(
            "tonic is not installed. Install it with: pip install tonic"
        ) from exc

    ds_name = _TONIC_DATASET_MAP[dataset_format]
    time_window_us = int(loader_config.get("time_window_ms", 1)) * 1000  # ms → µs
    train = bool(loader_config.get("train", True))

    ds_cls = getattr(tonic.datasets, ds_name, None)
    if ds_cls is None:
        raise DatasetLoadError(
            f"tonic.datasets.{ds_name} not found. Update tonic with: pip install --upgrade tonic"
        )

    sensor_size = getattr(ds_cls, "sensor_size", None)
    frame_transform = transforms.ToFrame(
        sensor_size=sensor_size,
        time_window=time_window_us,
    )
    save_to = str(source) if source.is_dir() else str(source.parent)
    dataset = ds_cls(save_to=save_to, train=train, transform=frame_transform)

    samples: list[EventSample] = []
    for idx, (frames, label) in enumerate(dataset):
        if max_samples is not None and idx >= max_samples:
            break
        # frames shape: (T, C, H, W) — store as fake events using frame indices
        arr = np.asarray(frames, dtype=np.float32)
        t_steps = arr.shape[0]
        t_idx = np.arange(t_steps, dtype=np.float32)
        samples.append(
            EventSample(
                label=int(label),
                x=t_idx,
                y=t_idx,
                t=t_idx,
                p=arr.reshape(t_steps, -1).mean(axis=1),
            )
        )
    if not samples:
        raise DatasetLoadError(
            f"tonic.datasets.{ds_name} returned no samples from '{save_to}'."
        )
    return samples


def _load_samples(
    source: Path,
    dataset_format: DatasetFormat,
    loader_config: dict[str, Any],
    *,
    max_samples: int | None,
) -> list[EventSample]:
    if dataset_format in _TONIC_FORMATS:
        return _load_tonic_samples(
            source, dataset_format, loader_config, max_samples=max_samples
        )
    if dataset_format == DatasetFormat.nmnist_bin:
        return _load_nmnist_directory(source, max_samples=max_samples)
    if dataset_format == DatasetFormat.hdf5_shd:
        return _load_hdf5_spike_dataset(source, loader_config, max_samples=max_samples)
    if dataset_format == DatasetFormat.hdf5_dvs_gesture:
        return _load_hdf5_event_dataset(source, loader_config, max_samples=max_samples)
    if dataset_format == DatasetFormat.hdf5_generic_event:
        return _load_hdf5_event_dataset(source, loader_config, max_samples=max_samples)
    if dataset_format == DatasetFormat.aedat:
        return _load_aedat_dataset(source, loader_config, max_samples=max_samples)
    if dataset_format == DatasetFormat.aedat4:
        return _load_aedat4_dataset(source, loader_config, max_samples=max_samples)
    if dataset_format == DatasetFormat.pt:
        return _load_pt_dataset(source, loader_config, max_samples=max_samples)
    raise DatasetLoadError(f"Dataset format '{dataset_format}' is not implemented.")


def _load_nmnist_directory(
    source: Path, *, max_samples: int | None
) -> list[EventSample]:
    root = source if source.is_dir() else source.parent
    if not root.is_dir():
        raise DatasetLoadError(
            f"N-MNIST dataset '{source}' must be a directory of class folders or .bin files."
        )
    samples: list[EventSample] = []
    class_dirs = sorted(
        [entry for entry in root.iterdir() if entry.is_dir()],
        key=lambda item: item.name,
    )
    if not class_dirs and source.suffix.lower() == ".bin":
        label = _parse_label_from_name(source.parent.name)
        return [_parse_nmnist_bin_file(source, label=label)]
    for class_dir in class_dirs:
        label = _parse_label_from_name(class_dir.name)
        for bin_file in sorted(class_dir.rglob("*.bin")):
            samples.append(_parse_nmnist_bin_file(bin_file, label=label))
            if max_samples is not None and len(samples) >= max_samples:
                return samples
    if not samples:
        raise DatasetLoadError(
            f"N-MNIST dataset '{source}' did not contain any .bin sample files."
        )
    return samples


def _parse_label_from_name(name: str) -> int:
    try:
        return int(name)
    except ValueError as exc:
        raise DatasetLoadError(
            f"Could not infer class label from folder '{name}'. "
            "Use numeric class directories for N-MNIST datasets."
        ) from exc


def _parse_nmnist_bin_file(path: Path, *, label: int) -> EventSample:
    raw = np.fromfile(path, dtype=np.uint8)
    if raw.size == 0 or raw.size % 5 != 0:
        raise DatasetLoadError(
            f"N-MNIST sample '{path}' is not a valid 5-byte event stream."
        )
    packets = raw.reshape(-1, 5)
    x = packets[:, 0].astype(np.int32)
    y_raw = packets[:, 1].astype(np.int32)
    p = ((packets[:, 2] & 0x80) >> 7).astype(np.int32)
    t = (
        ((packets[:, 2] & 0x7F).astype(np.int64) << 16)
        | (packets[:, 3].astype(np.int64) << 8)
        | packets[:, 4].astype(np.int64)
    )

    overflow_mask = y_raw == 240
    if overflow_mask.any():
        t = t + np.cumsum(overflow_mask.astype(np.int64)) * (1 << 13)
    keep = ~overflow_mask
    return EventSample(
        label=label,
        x=x[keep],
        y=y_raw[keep],
        t=t[keep],
        p=p[keep],
    )


def _load_hdf5_spike_dataset(
    source: Path,
    loader_config: dict[str, Any],
    *,
    max_samples: int | None,
) -> list[EventSample]:
    h5py = _import_h5py()
    labels_path = str(loader_config.get("labels_path", "labels"))
    units_path = str(loader_config.get("units_path", "spikes/units"))
    times_path = str(loader_config.get("times_path", "spikes/times"))

    with h5py.File(source, "r") as handle:
        labels = np.asarray(handle[labels_path], dtype=np.int32)
        units = handle[units_path]
        times = handle[times_path]
        samples: list[EventSample] = []
        total = len(labels)
        for index in range(total):
            if max_samples is not None and len(samples) >= max_samples:
                break
            sample_units = np.asarray(units[index], dtype=np.int32)
            sample_times = np.asarray(times[index], dtype=np.float64)
            if sample_units.shape != sample_times.shape:
                raise DatasetLoadError(
                    f"HDF5 spike dataset '{source}' has mismatched times/units at sample {index}."
                )
            samples.append(
                EventSample(
                    label=int(labels[index]),
                    x=sample_units,
                    y=np.zeros_like(sample_units),
                    t=_normalize_times(sample_times),
                    p=np.zeros_like(sample_units),
                )
            )
    if not samples:
        raise DatasetLoadError(
            f"HDF5 spike dataset '{source}' did not yield any samples."
        )
    return samples


def _load_hdf5_event_dataset(
    source: Path,
    loader_config: dict[str, Any],
    *,
    max_samples: int | None,
) -> list[EventSample]:
    h5py = _import_h5py()
    samples_path = loader_config.get("samples_path")
    labels_path = str(loader_config.get("labels_path", "labels"))

    with h5py.File(source, "r") as handle:
        if samples_path:
            dense = np.asarray(handle[str(samples_path)], dtype=np.float32)
            labels = np.asarray(handle[labels_path], dtype=np.int32)
            return _dense_tensor_to_samples(dense, labels, max_samples=max_samples)

        labels = np.asarray(handle[labels_path], dtype=np.int32)
        times = _read_hdf5_sequence(handle, loader_config, "times_path", "events/t")
        xs = _read_hdf5_sequence(handle, loader_config, "x_path", "events/x")
        ys = _read_hdf5_sequence(handle, loader_config, "y_path", "events/y")
        ps = _read_hdf5_sequence(
            handle, loader_config, "p_path", "events/p", optional=True
        )
        samples: list[EventSample] = []
        total = len(labels)
        for index in range(total):
            if max_samples is not None and len(samples) >= max_samples:
                break
            sample_t = np.asarray(times[index], dtype=np.float64)
            sample_x = np.asarray(xs[index], dtype=np.int32)
            sample_y = np.asarray(ys[index], dtype=np.int32)
            if ps is None:
                sample_p = np.zeros_like(sample_x)
            else:
                sample_p = np.asarray(ps[index], dtype=np.int32)
            samples.append(
                EventSample(
                    label=int(labels[index]),
                    x=sample_x,
                    y=sample_y,
                    t=_normalize_times(sample_t),
                    p=sample_p,
                )
            )
    if not samples:
        raise DatasetLoadError(
            f"HDF5 event dataset '{source}' did not yield any samples."
        )
    return samples


def _read_hdf5_sequence(
    handle: Any,
    loader_config: dict[str, Any],
    config_key: str,
    default_path: str,
    *,
    optional: bool = False,
) -> Any:
    path = str(loader_config.get(config_key, default_path))
    if path not in handle and optional:
        return None
    if path not in handle:
        raise DatasetLoadError(
            f"HDF5 dataset is missing required path '{path}'. "
            "Adjust loader_config in the dataset catalog entry."
        )
    return handle[path]


def pt_dense_tensors(source: Path | IO[bytes], *, label: str | None = None) -> tuple[
    np.ndarray[Any, Any],
    np.ndarray[Any, Any],
]:
    """Decode a ``.pt`` dataset into ``(data (N, T, F), labels (N,))``.

    Accepts a path or an open byte stream, because the API serves these files
    out of Jupyter's Contents API and never has them on disk.

    Supports the shapes the generated notebooks write:
    - ``TensorDataset(data_tensor, label_tensor)``
    - dict with keys ``data`` and ``labels``
    - bare ``(data_tensor, label_tensor)`` tuple

    ``(N, F)`` data gains a trivial timestep axis, so every caller sees rank 3.
    Split out of :func:`_load_pt_dataset` so the deploy path can read the same
    file the training path does without going through ``EventSample``.
    """
    try:
        import torch
    except ImportError as exc:
        raise DatasetLoadError(
            "PyTorch is required to load .pt datasets. Install it with: pip install torch"
        ) from exc

    name = label or (source.name if isinstance(source, Path) else "dataset.pt")

    torch.serialization.add_safe_globals([torch.utils.data.TensorDataset])
    try:
        raw = torch.load(source, weights_only=True)
    except Exception as exc:
        raise DatasetLoadError(
            f"Could not load '{name}' safely. "
            "Re-save your dataset with current PyTorch: "
            "torch.save(dataset, path) — then retry."
        ) from exc

    if hasattr(raw, "tensors"):
        # TensorDataset — attribute added by torch.utils.data.TensorDataset
        tensors = raw.tensors
        if len(tensors) < 2:
            raise DatasetLoadError(
                f"TensorDataset in '{name}' must have at least 2 tensors "
                "(data, labels). Found only 1."
            )
        data_np = tensors[0].detach().cpu().numpy()
        labels_np = tensors[1].long().detach().cpu().numpy()
    elif isinstance(raw, dict):
        if "data" not in raw or "labels" not in raw:
            raise DatasetLoadError(
                f"Dict .pt file '{name}' must have 'data' and 'labels' keys. "
                f"Found: {sorted(raw.keys())}"
            )
        data_np = (
            raw["data"].detach().cpu().numpy()
            if hasattr(raw["data"], "numpy")
            else raw["data"]
        )
        labels_np = (
            raw["labels"].detach().cpu().numpy()
            if hasattr(raw["labels"], "numpy")
            else raw["labels"]
        )
    elif isinstance(raw, tuple | list) and len(raw) >= 2:
        data_np = raw[0].detach().cpu().numpy() if hasattr(raw[0], "numpy") else raw[0]
        labels_np = (
            raw[1].detach().cpu().numpy() if hasattr(raw[1], "numpy") else raw[1]
        )
    else:
        raise DatasetLoadError(
            f"Unrecognised .pt format in '{name}'. "
            "Expected TensorDataset, dict with 'data'/'labels', or a (data, labels) tuple."
        )

    data_np = np.asarray(data_np, dtype=np.float32)
    labels_np = np.asarray(labels_np, dtype=np.int64)

    if data_np.ndim == 2:
        # (N, F) → add a trivial timestep axis → (N, 1, F)
        data_np = data_np[:, np.newaxis, :]

    return data_np, labels_np


def _load_pt_dataset(
    source: Path,
    loader_config: dict[str, Any],
    *,
    max_samples: int | None,
) -> list[EventSample]:
    """Load a PyTorch TensorDataset (.pt) file.

    Shapes and failure modes live in :func:`pt_dense_tensors`; this adds only
    the conversion to ``EventSample`` that the training path needs.
    """
    data_np, labels_np = pt_dense_tensors(source)
    return _dense_tensor_to_samples(data_np, labels_np, max_samples=max_samples)


def pt_feature_width(source: Path) -> int | None:
    """Feature width (F) of a ``.pt`` dataset, or None when it cannot be read.

    Mirrors ``pt_dense_tensors``'s three accepted layouts, but reads only the
    data tensor's ``shape`` — the file is memory-mapped where PyTorch allows
    it, so probing a 9000x784 dataset does not materialise 28 MB just to learn
    its second dimension.

    ``(N, F)`` reports F; ``(N, T, F)`` reports F, matching the width that
    reaches the first weighted module. Returns None — never raises — for
    anything unreadable, unrecognised, or of unexpected rank: callers use this
    to *improve* an error message, so a probe failure must never become the
    user's problem.
    """
    try:
        import torch
    except ImportError:
        return None

    try:
        torch.serialization.add_safe_globals([torch.utils.data.TensorDataset])
    except Exception:
        return None

    raw = None
    try:
        raw = torch.load(source, weights_only=True, mmap=True)
    except Exception:
        try:
            raw = torch.load(source, weights_only=True)
        except Exception:
            raw = None
    if raw is None:
        return None

    data = None
    if hasattr(raw, "tensors"):
        tensors = raw.tensors
        if len(tensors) >= 1:
            data = tensors[0]
    elif isinstance(raw, Mapping):
        data = raw.get("data")
    elif isinstance(raw, tuple | list) and len(raw) >= 1:
        data = raw[0]
    elif hasattr(raw, "shape"):
        # A bare tensor — the notebook codegen path accepts this layout too.
        data = raw

    shape = getattr(data, "shape", None)
    if shape is None:
        return None
    try:
        dims = tuple(int(d) for d in shape)
    except Exception:
        return None
    if len(dims) not in (2, 3):
        return None
    return dims[-1]


def _dense_tensor_to_samples(
    dense: np.ndarray[Any, Any],
    labels: np.ndarray[Any, Any],
    *,
    max_samples: int | None,
) -> list[EventSample]:
    if dense.ndim != 3:
        raise DatasetLoadError(
            f"Dense event tensor must have shape [samples, timesteps, features], got {dense.shape}."
        )
    total = dense.shape[0]
    if labels.shape[0] != total:
        raise DatasetLoadError(
            f"Dense event tensor has {total} samples but labels has {labels.shape[0]} rows."
        )
    samples: list[EventSample] = []
    count = total if max_samples is None else min(total, max_samples)
    for index in range(count):
        coords = np.argwhere(dense[index] > 0)
        if coords.size == 0:
            x = np.zeros(0, dtype=np.int32)
            y = np.zeros(0, dtype=np.int32)
            t = np.zeros(0, dtype=np.int64)
            p = np.zeros(0, dtype=np.int32)
        else:
            t = coords[:, 0].astype(np.int64)
            x = coords[:, 1].astype(np.int32)
            y = np.zeros_like(x)
            p = np.zeros_like(x)
        samples.append(
            EventSample(
                label=int(labels[index]),
                x=x,
                y=y,
                t=t,
                p=p,
            )
        )
    return samples


def _load_aedat_dataset(
    source: Path,
    loader_config: dict[str, Any],
    *,
    max_samples: int | None,
) -> list[EventSample]:
    sample_paths = _sample_paths_from_source(
        source, suffixes={".aedat", ".dat"}, max_samples=max_samples
    )
    samples: list[EventSample] = []
    for sample_path in sample_paths:
        label = _infer_label_from_path(sample_path, loader_config)
        samples.append(
            _parse_aedat_v2_file(sample_path, label=label, loader_config=loader_config)
        )
    if not samples:
        raise DatasetLoadError(
            f"AEDAT dataset '{source}' did not contain any supported event files."
        )
    return samples


def _load_aedat4_dataset(
    source: Path,
    loader_config: dict[str, Any],
    *,
    max_samples: int | None,
) -> list[EventSample]:
    try:
        import dv_processing as dv
    except ImportError:
        try:
            import dv
        except ImportError as exc:
            raise DatasetLoadError(
                "AEDAT4 support requires the optional 'dv-processing' Python package. "
                "Install it in the training environment or convert the dataset to HDF5/AEDAT v2."
            ) from exc
    sample_paths = _sample_paths_from_source(
        source, suffixes={".aedat4"}, max_samples=max_samples
    )
    samples: list[EventSample] = []
    for sample_path in sample_paths:
        label = _infer_label_from_path(sample_path, loader_config)
        xs: list[int] = []
        ys: list[int] = []
        ts: list[int] = []
        ps: list[int] = []
        with dv.AedatFile(str(sample_path)) as recording:
            for packet in recording["events"].numpy():
                xs.extend(packet["x"].astype(np.int32).tolist())
                ys.extend(packet["y"].astype(np.int32).tolist())
                ts.extend(packet["timestamp"].astype(np.int64).tolist())
                ps.extend(packet["polarity"].astype(np.int32).tolist())
        samples.append(
            EventSample(
                label=label,
                x=np.asarray(xs, dtype=np.int32),
                y=np.asarray(ys, dtype=np.int32),
                t=_normalize_times(np.asarray(ts, dtype=np.int64)),
                p=np.asarray(ps, dtype=np.int32),
            )
        )
    if not samples:
        raise DatasetLoadError(
            f"AEDAT4 dataset '{source}' did not contain any readable .aedat4 samples."
        )
    return samples


def _sample_paths_from_source(
    source: Path,
    *,
    suffixes: set[str],
    max_samples: int | None,
) -> list[Path]:
    if source.is_file():
        return [source]
    paths = sorted(
        [
            item
            for item in source.rglob("*")
            if item.is_file() and item.suffix.lower() in suffixes
        ]
    )
    if max_samples is not None:
        return paths[:max_samples]
    return paths


def _infer_label_from_path(sample_path: Path, loader_config: dict[str, Any]) -> int:
    label_map_raw = loader_config.get("label_map")
    if isinstance(label_map_raw, str):
        try:
            label_map_raw = json.loads(label_map_raw)
        except json.JSONDecodeError as exc:
            raise DatasetLoadError(
                "loader_config.label_map must be valid JSON."
            ) from exc
    if isinstance(label_map_raw, Mapping):
        for key, value in label_map_raw.items():
            if key in sample_path.parts:
                return int(value)
    for candidate in (sample_path.parent.name, sample_path.parent.parent.name):
        try:
            return int(candidate)
        except ValueError:
            continue
    raise DatasetLoadError(
        f"Could not infer label for '{sample_path}'. "
        "Provide loader_config.label_map or numeric class directories."
    )


def _parse_aedat_v2_file(
    path: Path, *, label: int, loader_config: dict[str, Any]
) -> EventSample:
    with path.open("rb") as handle:
        while True:
            pos = handle.tell()
            line = handle.readline()
            if not line.startswith(b"#"):
                handle.seek(pos)
                break
        payload = handle.read()
    if len(payload) % 8 != 0:
        raise DatasetLoadError(
            f"AEDAT file '{path}' has an invalid 8-byte event payload."
        )

    x_mask = int(loader_config.get("x_mask", 0x00FE))
    x_shift = int(loader_config.get("x_shift", 1))
    y_mask = int(loader_config.get("y_mask", 0x7F00))
    y_shift = int(loader_config.get("y_shift", 8))
    p_mask = int(loader_config.get("p_mask", 0x1))
    p_shift = int(loader_config.get("p_shift", 0))

    event_count = len(payload) // 8
    xs = np.zeros(event_count, dtype=np.int32)
    ys = np.zeros(event_count, dtype=np.int32)
    ts = np.zeros(event_count, dtype=np.int64)
    ps = np.zeros(event_count, dtype=np.int32)

    for index, (address, timestamp) in enumerate(struct.iter_unpack(">II", payload)):
        xs[index] = (address & x_mask) >> x_shift
        ys[index] = (address & y_mask) >> y_shift
        ps[index] = (address & p_mask) >> p_shift
        ts[index] = timestamp

    return EventSample(
        label=label,
        x=xs,
        y=ys,
        t=_normalize_times(ts),
        p=ps,
    )


def _samples_to_fixture(
    *,
    dataset_name: str,
    dataset_path: str,
    dataset_format: str,
    samples: list[EventSample],
    timesteps: int,
    sensor_width: int,
    sensor_height: int,
) -> EventDatasetFixture:
    if not samples:
        raise DatasetLoadError("Dataset loader did not produce any samples.")
    inferred_width = max(
        [int(sample.x.max()) + 1 for sample in samples if sample.x.size],
        default=1,
    )
    inferred_height = max(
        [int(sample.y.max()) + 1 for sample in samples if sample.y.size],
        default=1,
    )
    width = sensor_width or inferred_width
    height = sensor_height or inferred_height
    if width <= 0 or height <= 0:
        raise DatasetLoadError("Dataset sensor dimensions must be positive.")
    input_size = width * height * 2

    dense_samples: list[list[list[float]]] = []
    labels: list[int] = []
    for sample in samples:
        dense_samples.append(_bin_sample(sample, timesteps, width, height))
        labels.append(sample.label)
    return EventDatasetFixture(
        name=dataset_name,
        samples=dense_samples,
        labels=labels,
        num_classes=len(set(labels)),
        input_size=input_size,
        timesteps=timesteps,
        synthetic=False,
        dataset_id=dataset_name,
        source_path=dataset_path,
        source_format=dataset_format,
    )


def _bin_sample(
    sample: EventSample, timesteps: int, width: int, height: int
) -> list[list[float]]:
    dense = np.zeros((timesteps, width * height * 2), dtype=np.float32)
    if sample.t.size == 0:
        empty: list[list[float]] = dense.tolist()
        return empty
    t_min = int(sample.t.min())
    t_max = int(sample.t.max())
    span = max(t_max - t_min, 1)
    for x, y, t, p in zip(sample.x, sample.y, sample.t, sample.p, strict=False):
        if x < 0 or y < 0 or x >= width or y >= height:
            continue
        timestep = min(int(((int(t) - t_min) / span) * (timesteps - 1)), timesteps - 1)
        polarity = 1 if int(p) else 0
        feature = polarity * width * height + int(y) * width + int(x)
        dense[timestep, feature] += 1.0
    result: list[list[float]] = dense.tolist()
    return result


def _normalize_times(values: np.ndarray[Any, Any]) -> np.ndarray[Any, Any]:
    if values.size == 0:
        return np.zeros(0, dtype=np.int64)
    as_int = values.astype(np.float64)
    minimum = float(as_int.min())
    shifted = as_int - minimum
    return np.asarray(np.rint(shifted).astype(np.int64))


def _import_h5py() -> Any:
    try:
        import h5py
    except ImportError as exc:
        raise DatasetLoadError(
            "HDF5 dataset loading requires the optional 'h5py' package in the training environment."
        ) from exc
    return h5py
