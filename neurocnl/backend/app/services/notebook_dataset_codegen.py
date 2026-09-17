"""Dataset-loading notebook codegen for `backend.app.routers.notebook`.

Mechanical extraction of the six functions/constants that generate the
"load a dataset into train/test DataLoaders" cell for a notebook target:
`_TONIC_DATASET_CLASS`, `_TONIC_EXTRA_CTOR_KWARGS`, `_pt_loading_code`,
`_pt_named_loading_code`, `_spike_generator_code`, and `_dataset_loading_code`
itself (which dispatches to the tonic/pt/custom/catalog branches). Bodies are
copied verbatim — behavior, strings, and comments are unchanged.

These previously lived in `backend.app.routers.notebook` and were imported
back into `notebook_dag_node_emitters.py` via local (in-function) imports to
avoid a circular import (`notebook.py` imports `dag_node_code` from that
module at its own module-scope). This module has no dependency on
`notebook.py` or `notebook_dag_node_emitters.py`, so it can be imported at
module scope from both, and `notebook.py` re-exports these names instead of
defining them, for the test suite's existing
`from backend.app.routers.notebook import _dataset_loading_code`-style
imports.
"""

from __future__ import annotations

_TONIC_DATASET_CLASS: dict[str, str] = {
    "tonic_nmnist": "NMNIST",
    "tonic_shd": "SHD",
    "tonic_ntidigits": "NTIDIGITS18",
}

# Extra constructor kwargs a tonic dataset class needs beyond save_to/train/transform.
# NTIDIGITS18 defaults to returning connected-digit-sequence labels (e.g. "6-9-3");
# single_digits=True is what makes it return one int class per sample instead, which
# is what a single-label classification pipeline (ceCountLoss, Accuracy) requires.
_TONIC_EXTRA_CTOR_KWARGS: dict[str, str] = {
    "NTIDIGITS18": ", single_digits=True",
}


def _pt_loading_code(path: str, batch_size: int, shuffle: bool) -> str:
    """Return a self-contained Python snippet that loads a .pt dataset."""
    shuffle_str = "True" if shuffle else "False"
    path_repr = repr(path)
    return (
        "import torch\n"
        "from torch.serialization import safe_globals\n"
        "from torch.utils.data import DataLoader, TensorDataset\n\n"
        "try:\n"
        "    with safe_globals([TensorDataset]):\n"
        f"        _raw = torch.load({path_repr}, weights_only=True)\n"
        "except FileNotFoundError as exc:\n"
        "    raise RuntimeError(\n"
        f"        'Dataset file not found: ' + {path_repr} + '. '\n"
        "        'This file does not exist yet — if it is a hand-built stimulus/dataset, "
        "generate it first (see the notebook guide\\'s data-preparation step), then retry.'\n"
        "    ) from exc\n"
        "except Exception as exc:\n"
        "    raise RuntimeError(\n"
        f"        'Could not safely load trusted .pt dataset ' + {path_repr} + '. '\n"
        "        'Expected a TensorDataset, tuple/list of tensors, a bare tensor, "
        "or a dict with data/labels. '\n"
        "        'Regenerate the dataset in one of those formats, then retry.'\n"
        "    ) from exc\n"
        "# Handle TensorDataset, dict, raw tuple, or a bare tensor (e.g. an\n"
        "# unlabeled stimulus/spike-train tensor with no dataset wrapper)\n"
        "_ds = _raw if hasattr(_raw, 'tensors') else "
        "TensorDataset(*_raw) if isinstance(_raw, (tuple, list)) "
        "else TensorDataset(_raw) if torch.is_tensor(_raw) "
        "else TensorDataset(_raw['data'], _raw['labels'])\n\n"
        f"train_loader = DataLoader(_ds, batch_size={batch_size}, shuffle={shuffle_str}, num_workers=0)\n"
        f"test_loader  = DataLoader(_ds, batch_size={batch_size}, shuffle=False,          num_workers=0)\n"
        f"print(f'.pt dataset: {{len(_ds)}} samples, batch_size={batch_size}')"
    )


def _pt_named_loading_code(
    path: str,
    batch_size: int,
    loader_var: str = "val_loader",
    label: str = "validation",
) -> str:
    """Like `_pt_loading_code` but binds exactly one loader, named `loader_var`.

    Never touches the other loaders — a dedicated validation dataset (wired
    into `validationLoop`'s `val_data` port) or a dedicated `testLoader` node
    carries its own path/batch_size and must not clobber the phase's other
    loader variables when several are present in the same setup block.
    """
    path_repr = repr(path)
    stem = loader_var.removesuffix("_loader")  # val_loader -> val, test_loader -> test
    ds_var = f"_{stem}_ds"
    raw_var = f"_{stem}_raw"
    return (
        "import torch\n"
        "from torch.serialization import safe_globals\n"
        "from torch.utils.data import DataLoader, TensorDataset\n\n"
        "try:\n"
        "    with safe_globals([TensorDataset]):\n"
        f"        {raw_var} = torch.load({path_repr}, weights_only=True)\n"
        "except FileNotFoundError as exc:\n"
        "    raise RuntimeError(\n"
        f"        '{label.capitalize()} dataset file not found: ' + {path_repr} + '. '\n"
        "        'Generate it first, then retry.'\n"
        "    ) from exc\n"
        "except Exception as exc:\n"
        "    raise RuntimeError(\n"
        f"        'Could not safely load trusted .pt {label} dataset ' + {path_repr} + '. '\n"
        "        'Expected a TensorDataset, tuple/list of tensors, a bare tensor, "
        "or a dict with data/labels.'\n"
        "    ) from exc\n"
        f"{ds_var} = {raw_var} if hasattr({raw_var}, 'tensors') else "
        f"TensorDataset(*{raw_var}) if isinstance({raw_var}, (tuple, list)) "
        f"else TensorDataset({raw_var}) if torch.is_tensor({raw_var}) "
        f"else TensorDataset({raw_var}['data'], {raw_var}['labels'])\n\n"
        f"{loader_var} = DataLoader({ds_var}, batch_size={batch_size}, shuffle=False, num_workers=0)\n"
        f"print(f'.pt {label} dataset: {{len({ds_var})}} samples, batch_size={batch_size}')"
    )


def _spike_generator_code(
    n_neurons: int,
    n_timesteps: int,
    pattern: str,
    isi_period: int,
    rate_hz: float,
    seed: int,
) -> str:
    """Generate Python code that creates a synthetic spike dataset in memory."""
    isi_period = max(1, isi_period)  # guard against slice step = 0
    rate_hz = max(1e-6, rate_hz)  # guard against division by zero
    if pattern == "isi_regular":
        pattern_code = (
            f"_spikes = torch.zeros(_n_timesteps, _n_neurons)\n"
            f"_spikes[{isi_period - 1}::{isi_period}] = 1.0  # fire every {isi_period} steps"
        )
    elif pattern == "poisson":
        pattern_code = (
            f"_rate   = {rate_hz} / 1000.0  # Hz → probability per ms timestep\n"
            "_spikes = (torch.rand(_n_timesteps, _n_neurons) < _rate).float()"
        )
    elif pattern == "constant_rate":
        pattern_code = (
            f"_interval = max(1, round(1000.0 / {rate_hz}))  # ms between spikes\n"
            "_spikes   = torch.zeros(_n_timesteps, _n_neurons)\n"
            "_spikes[::_interval] = 1.0"
        )
    else:
        pattern_code = "_spikes = torch.zeros(_n_timesteps, _n_neurons)"
    return (
        "import torch\n"
        "from torch.utils.data import DataLoader, TensorDataset\n\n"
        f"torch.manual_seed({seed})\n"
        f"_n_neurons   = {n_neurons}\n"
        f"_n_timesteps = {n_timesteps}\n"
        f"_n_samples   = 1  # single synthetic sample\n\n" + pattern_code + "\n\n"
        "_labels = torch.zeros(_n_samples, dtype=torch.long)\n"
        "_ds = TensorDataset(_spikes.unsqueeze(0), _labels)  # (1, T, N)\n"
        f"train_loader = DataLoader(_ds, batch_size=1, shuffle=False)\n"
        f"test_loader  = DataLoader(_ds, batch_size=1, shuffle=False)\n"
        f"print(f'Spike generator: {{_n_timesteps}} timesteps x {{_n_neurons}} neurons ({pattern})')"
    )


def _dataset_loading_code(
    dataset: str,
    batch_size: int,
    custom_path: str = "",
    time_window_ms: int = 1,
) -> str:
    """Return Python code that loads train/test DataLoaders for the given dataset.

    `time_window_ms` mirrors the `dataLoader` DAG node's parameter of the same
    name and is only consulted by the event-stream (tonic) branches, whose
    samples are variable-length and therefore need both a `ToFrame` binning
    transform and a padding collate to batch at all.
    """
    if not dataset:
        return (
            "import torch\n"
            "from torch.utils.data import DataLoader\n"
            "# No dataset selected — replace with your own DataLoader.\n"
            f"# train_loader = DataLoader(train_ds, batch_size={batch_size}, shuffle=True)\n"
            f"# test_loader  = DataLoader(test_ds,  batch_size={batch_size}, shuffle=False)\n"
        )
    if dataset in ("NMNIST", "tonic_nmnist"):
        return (
            "import torch\n"
            "from torch.utils.data import DataLoader\n"
            "try:\n"
            "    import tonic\n"
            "    import tonic.transforms as _tf\n"
            "    _sensor_size = tonic.datasets.NMNIST.sensor_size\n"
            "    _frame_tf = _tf.ToFrame(sensor_size=_sensor_size, n_time_bins=25)  # ponytail: fixed bins so all samples have same T; matches num_steps\n"
            "    train_ds = tonic.datasets.NMNIST(save_to='data/', train=True,  transform=_frame_tf)\n"
            "    test_ds  = tonic.datasets.NMNIST(save_to='data/', train=False, transform=_frame_tf)\n"
            "except ImportError:\n"
            "    raise ImportError('pip install tonic')\n"
            f"train_loader = DataLoader(train_ds, batch_size={batch_size}, shuffle=True,  num_workers=0)\n"
            f"test_loader  = DataLoader(test_ds,  batch_size={batch_size}, shuffle=False, num_workers=0)\n"
            f"print(f'N-MNIST: {{len(train_loader.dataset)}} train / {{len(test_loader.dataset)}} test samples')"
        )
    elif dataset in ("SHD", "tonic_shd"):
        # Raw SHD samples are variable-length event streams: without ToFrame
        # binning plus PadTensors they cannot be collated into a batch at all.
        # batch_first=False matches the (T,B,...) shape the generated
        # forward() iterates over — see `_dag_node_code`'s tonic_* branch.
        return (
            "import torch\n"
            "from torch.utils.data import DataLoader\n"
            "try:\n"
            "    import tonic\n"
            "    import tonic.transforms as _tf\n"
            "    _sensor_size = tonic.datasets.SHD.sensor_size\n"
            f"    _frame_tf = _tf.ToFrame(sensor_size=_sensor_size, time_window={time_window_ms * 1000})\n"
            "    _pad_collate = tonic.collation.PadTensors(batch_first=False)\n"
            "    train_ds = tonic.datasets.SHD(save_to='data/', train=True,  transform=_frame_tf)\n"
            "    test_ds  = tonic.datasets.SHD(save_to='data/', train=False, transform=_frame_tf)\n"
            "except ImportError:\n"
            "    raise ImportError('pip install tonic')\n"
            f"train_loader = DataLoader(train_ds, batch_size={batch_size}, shuffle=True,  num_workers=0, collate_fn=_pad_collate)\n"
            f"test_loader  = DataLoader(test_ds,  batch_size={batch_size}, shuffle=False, num_workers=0, collate_fn=_pad_collate)\n"
            f"print(f'SHD: {{len(train_loader.dataset)}} train / {{len(test_loader.dataset)}} test samples')"
        )
    elif dataset == "N-TIDIGITS":
        return (
            "import torch\n"
            "from torch.utils.data import DataLoader\n"
            "try:\n"
            "    import tonic\n"
            "    train_ds = tonic.datasets.NTIDIGITS(save_to='data/', train=True)\n"
            "    test_ds  = tonic.datasets.NTIDIGITS(save_to='data/', train=False)\n"
            "except ImportError:\n"
            "    raise ImportError('pip install tonic')\n"
            f"train_loader = DataLoader(train_ds, batch_size={batch_size}, shuffle=True,  num_workers=0)\n"
            f"test_loader  = DataLoader(test_ds,  batch_size={batch_size}, shuffle=False, num_workers=0)\n"
        )
    elif dataset == "custom":
        if custom_path:
            return _pt_loading_code(custom_path, batch_size=batch_size, shuffle=True)
        return (
            "import torch\n"
            "from torch.utils.data import DataLoader\n"
            "# No custom dataset path configured on the Data Loader node.\n"
            f"# train_ds = torch.load('./my_dataset/train.pt')\n"
            f"# test_ds  = torch.load('./my_dataset/test.pt')\n"
            f"# train_loader = DataLoader(train_ds, batch_size={batch_size}, shuffle=True)\n"
            f"# test_loader  = DataLoader(test_ds,  batch_size={batch_size}, shuffle=False)\n"
            "raise NotImplementedError(\n"
            "    'Set dataset_path on the Data Loader node, then regenerate the notebook.'\n"
            ")"
        )
    # Local import (not module-scope): tests patch
    # `backend.app.routers.notebook.load_dataset_catalog`, and notebook.py
    # re-exports this function, so the lookup must go through notebook.py's
    # module namespace rather than this module's own import binding.
    from backend.app.routers.notebook import load_dataset_catalog

    entry = load_dataset_catalog().get(dataset)
    if entry is not None and entry.format == "nmnist_bin":
        # nmnist_bin *is* N-MNIST's own raw binary format — safe to reuse the
        # real tonic.datasets.NMNIST loader above rather than a placeholder.
        return _dataset_loading_code("NMNIST", batch_size, custom_path)
    if entry is not None:
        return (
            "import torch\n"
            "from torch.utils.data import DataLoader\n"
            f"# Catalog dataset '{entry.label}' ({entry.format or 'unknown format'}): {entry.description}\n"
            f"# Storage path: {entry.storage_path}\n"
            "# No built-in loader for this format yet — mount the file above and replace with your DataLoader.\n"
            f"# train_loader = DataLoader(..., batch_size={batch_size}, shuffle=True)\n"
            f"# test_loader  = DataLoader(..., batch_size={batch_size}, shuffle=False)\n"
        )
    return (
        "import torch\n"
        "from torch.utils.data import DataLoader\n"
        f"# Dataset '{dataset}' — replace with your DataLoader\n"
        f"# train_loader = DataLoader(..., batch_size={batch_size}, shuffle=True)\n"
        f"# test_loader  = DataLoader(..., batch_size={batch_size}, shuffle=False)\n"
    )
