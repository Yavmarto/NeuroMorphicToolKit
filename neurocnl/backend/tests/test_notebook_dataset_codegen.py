"""Tests for ``backend.app.services.notebook_dataset_codegen`` (dataset /
spike-generator loading-code emitters). Exercises the ``_pt_loading_code``
and ``_spike_generator_code`` emitters, which are re-exported from
``backend.app.routers.notebook``.
"""

from __future__ import annotations

import pytest

from backend.app.routers.notebook import _pt_loading_code, _spike_generator_code


def test_pt_loading_code_tensordataset() -> None:
    code = _pt_loading_code("data/ds_train.pt", batch_size=64, shuffle=True)
    assert "torch.load" in code
    assert "data/ds_train.pt" in code
    assert "safe_globals([TensorDataset])" in code
    assert "weights_only=True" in code
    assert "weights_only=False" not in code
    assert "batch_size=64" in code
    assert "shuffle=True" in code
    assert "test_loader" in code


def test_pt_loading_code_no_shuffle() -> None:
    code = _pt_loading_code("data/ds_test.pt", batch_size=32, shuffle=False)
    assert "shuffle=False" in code
    assert "train_loader" in code


def test_pt_loading_code_is_syntactically_valid() -> None:
    """Regression: the generated RuntimeError message previously spliced a
    Python repr() string (with its own quotes) inside an already-quoted
    template literal, producing a SyntaxError in every generated notebook
    that used a `.pt` Data Loader — never caught because prior tests only
    substring-matched the source instead of compiling it."""
    for path in ("data/ds_train.pt", "paper/01_lif/data/lif_stimulus_d.pt", "it's.pt"):
        code = _pt_loading_code(path, batch_size=32, shuffle=True)
        compile(code, "<generated>", "exec")


def test_pt_loading_code_handles_bare_tensor(tmp_path) -> None:
    """Regression: a `.pt` file holding a bare (unlabeled) tensor — e.g. a
    stimulus/spike-train saved with plain `torch.save(tensor, ...)`, not
    wrapped in a TensorDataset — must load, not IndexError on `_raw['data']`."""
    torch = pytest.importorskip("torch")

    ds_path = tmp_path / "stimulus.pt"
    torch.save(torch.zeros(10, 1), ds_path)

    code = _pt_loading_code(str(ds_path), batch_size=4, shuffle=True)
    namespace: dict = {}
    exec(compile(code, "<generated>", "exec"), namespace)
    assert len(namespace["train_loader"].dataset) == 10


def test_spike_gen_isi_regular() -> None:
    code = _spike_generator_code(
        n_neurons=1,
        n_timesteps=100,
        pattern="isi_regular",
        isi_period=10,
        rate_hz=10.0,
        seed=42,
    )
    assert "torch.zeros" in code
    assert "10" in code
    assert "train_loader" in code
    assert "test_loader" in code


def test_spike_gen_poisson() -> None:
    code = _spike_generator_code(
        n_neurons=4,
        n_timesteps=256,
        pattern="poisson",
        isi_period=10,
        rate_hz=50.0,
        seed=0,
    )
    assert "torch.rand" in code
    assert "50.0" in code


def test_spike_gen_constant_rate() -> None:
    code = _spike_generator_code(
        n_neurons=1,
        n_timesteps=100,
        pattern="constant_rate",
        isi_period=10,
        rate_hz=100.0,
        seed=7,
    )
    assert "1000.0" in code
    assert "100.0" in code
