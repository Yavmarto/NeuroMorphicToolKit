from __future__ import annotations

import struct
from pathlib import Path

import pytest

from neurocnl.training.dataset_loader import DatasetLoadError, load_event_dataset


def test_load_event_dataset_from_dense_hdf5(tmp_path: Path) -> None:
    h5py = pytest.importorskip("h5py")
    dataset_path = tmp_path / "dense.h5"
    with h5py.File(dataset_path, "w") as handle:
        handle.create_dataset(
            "samples",
            data=[
                [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]],
                [[0.0, 0.0, 1.0], [1.0, 0.0, 0.0]],
            ],
        )
        handle.create_dataset("labels", data=[0, 1])

    fixture = load_event_dataset(
        dataset_name="nmnist",
        dataset_path=str(dataset_path),
        dataset_format="hdf5_generic_event",
        loader_config={"samples_path": "samples", "labels_path": "labels"},
        timesteps=2,
        max_samples=2,
    )

    assert fixture.synthetic is False
    assert fixture.source_format == "hdf5_generic_event"
    assert fixture.dataset_id == "nmnist"
    assert fixture.num_classes == 2
    assert len(fixture.samples) == 2


def test_load_event_dataset_from_nmnist_binary_directory(tmp_path: Path) -> None:
    class_dir = tmp_path / "0"
    class_dir.mkdir(parents=True)
    sample_path = class_dir / "sample.bin"
    sample_path.write_bytes(
        b"".join(
            [
                _nmnist_event_bytes(1, 2, 0, 5),
                _nmnist_event_bytes(2, 3, 1, 8),
            ]
        )
    )

    fixture = load_event_dataset(
        dataset_name="nmnist",
        dataset_path=str(tmp_path),
        dataset_format="nmnist_bin",
        timesteps=4,
        max_samples=1,
    )

    assert fixture.synthetic is False
    assert fixture.labels == [0]
    assert fixture.timesteps == 4
    assert len(fixture.samples) == 1
    assert any(value > 0 for row in fixture.samples[0] for value in row)


def test_load_event_dataset_from_aedat_v2(tmp_path: Path) -> None:
    sample_dir = tmp_path / "3"
    sample_dir.mkdir(parents=True)
    sample_path = sample_dir / "gesture.aedat"
    sample_path.write_bytes(
        b"# test header\n"
        + struct.pack(">II", 0x00000104, 100)
        + struct.pack(">II", 0x00000208, 200)
    )

    fixture = load_event_dataset(
        dataset_name="gesture",
        dataset_path=str(tmp_path),
        dataset_format="aedat",
        timesteps=3,
        max_samples=1,
    )

    assert fixture.synthetic is False
    assert fixture.labels == [3]
    assert fixture.source_format == "aedat"


def test_load_event_dataset_missing_path_raises(tmp_path: Path) -> None:
    with pytest.raises(DatasetLoadError, match="does not exist"):
        load_event_dataset(
            dataset_name="missing",
            dataset_path=str(tmp_path / "missing.h5"),
            dataset_format="hdf5_generic_event",
        )


def test_pt_format_resolved_from_extension(tmp_path: Path) -> None:
    torch = pytest.importorskip("torch")
    pt_path = tmp_path / "ds.pt"
    ds = torch.utils.data.TensorDataset(
        torch.zeros(4, 10, 3),
        torch.tensor([0, 1, 0, 1]),
    )
    torch.save(ds, pt_path)

    fixture = load_event_dataset(
        dataset_name="braille",
        dataset_path=str(pt_path),
        dataset_format=None,  # auto-infer from .pt extension
        timesteps=10,
        max_samples=4,
    )

    assert fixture.source_format == "pt"
    assert fixture.synthetic is False
    assert len(fixture.samples) == 4
    assert fixture.num_classes == 2


def test_pt_format_explicit_string(tmp_path: Path) -> None:
    torch = pytest.importorskip("torch")
    pt_path = tmp_path / "weirdname.bin"
    ds = torch.utils.data.TensorDataset(
        torch.ones(2, 5, 12),
        torch.tensor([3, 6]),
    )
    torch.save(ds, pt_path)

    fixture = load_event_dataset(
        dataset_name="braille",
        dataset_path=str(pt_path),
        dataset_format="pt",  # explicit override
        timesteps=5,
        max_samples=2,
    )

    assert fixture.source_format == "pt"
    assert fixture.num_classes == 2


def test_pt_dict_format(tmp_path: Path) -> None:
    torch = pytest.importorskip("torch")
    pt_path = tmp_path / "dict_ds.pt"
    torch.save(
        {"data": torch.zeros(3, 8, 4), "labels": torch.tensor([0, 1, 2])},
        pt_path,
    )

    fixture = load_event_dataset(
        dataset_name="custom",
        dataset_path=str(pt_path),
        dataset_format="pt",
        timesteps=8,
        max_samples=3,
    )

    assert len(fixture.samples) == 3
    assert fixture.num_classes == 3


def _nmnist_event_bytes(x: int, y: int, polarity: int, timestamp: int) -> bytes:
    high = (timestamp >> 16) & 0x7F
    mid = (timestamp >> 8) & 0xFF
    low = timestamp & 0xFF
    polarity_byte = (polarity << 7) | high
    return bytes([x, y, polarity_byte, mid, low])


# ── pt_feature_width: shape-only probe used to pre-check model input width ─────


def test_pt_feature_width_reads_2d_tensordataset(tmp_path: Path) -> None:
    """(N, F) reports F — the MNIST layout the guides document."""
    torch = pytest.importorskip("torch")
    from neurocnl.training.dataset_loader import pt_feature_width

    pt_path = tmp_path / "mnist_train.pt"
    ds = torch.utils.data.TensorDataset(torch.zeros(9, 784), torch.zeros(9, dtype=torch.long))
    torch.save(ds, pt_path)

    assert pt_feature_width(pt_path) == 784


def test_pt_feature_width_reads_3d_tensordataset(tmp_path: Path) -> None:
    """(N, T, F) also reports F — the width that reaches the first weighted layer."""
    torch = pytest.importorskip("torch")
    from neurocnl.training.dataset_loader import pt_feature_width

    pt_path = tmp_path / "seq.pt"
    ds = torch.utils.data.TensorDataset(torch.zeros(4, 25, 12), torch.zeros(4, dtype=torch.long))
    torch.save(ds, pt_path)

    assert pt_feature_width(pt_path) == 12


def test_pt_feature_width_reads_dict_layout(tmp_path: Path) -> None:
    torch = pytest.importorskip("torch")
    from neurocnl.training.dataset_loader import pt_feature_width

    pt_path = tmp_path / "dict.pt"
    torch.save({"data": torch.zeros(3, 196), "labels": torch.zeros(3, dtype=torch.long)}, pt_path)

    assert pt_feature_width(pt_path) == 196


def test_pt_feature_width_returns_none_for_unreadable_file(tmp_path: Path) -> None:
    """Callers use this to improve an error message, so a probe failure is never fatal."""
    from neurocnl.training.dataset_loader import pt_feature_width

    junk = tmp_path / "junk.pt"
    junk.write_bytes(b"not a torch archive")

    assert pt_feature_width(junk) is None
    assert pt_feature_width(tmp_path / "absent.pt") is None
