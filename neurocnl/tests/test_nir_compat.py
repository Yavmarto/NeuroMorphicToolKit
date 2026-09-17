# neurocnl/tests/test_nir_compat.py
"""Tests for _nir_compat shims — safe_nir_read() and make_nir_graph() fallback."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import nir
import numpy as np
import pytest

from neurocnl._nir_compat import make_nir_graph, safe_nir_read

# ---------------------------------------------------------------------------
# safe_nir_read: happy path
# ---------------------------------------------------------------------------


def test_safe_nir_read_delegates_to_nir_read_on_success():
    """When nir.read() succeeds, safe_nir_read returns its result unchanged."""
    fake_graph = MagicMock(spec=nir.NIRGraph)
    with patch("neurocnl._nir_compat.nir.read", return_value=fake_graph) as mock_read:
        result = safe_nir_read("/some/file.nir")
    mock_read.assert_called_once_with("/some/file.nir")
    assert result is fake_graph


# ---------------------------------------------------------------------------
# safe_nir_read: type_check mismatch — fallback path
# ---------------------------------------------------------------------------


def test_safe_nir_read_falls_back_on_type_check_error():
    """When nir.read() raises TypeError about 'type_check', fallback HDF5 path is used."""
    fake_graph = MagicMock(spec=nir.NIRGraph)
    type_check_error = TypeError(
        "NIRGraph.__init__() got an unexpected keyword argument 'type_check'"
    )

    fake_data = {"some": "data"}

    with (
        patch("neurocnl._nir_compat.nir.read", side_effect=type_check_error),
        patch("neurocnl._nir_compat.h5py") as mock_h5py,
        patch("neurocnl._nir_compat.hdf2dict", return_value=fake_data),
        patch("neurocnl._nir_compat.nir.dict2NIRNode", return_value=fake_graph) as mock_dict2nir,
    ):
        # h5py.File context manager setup
        mock_file = MagicMock()
        mock_file.__enter__ = MagicMock(return_value=mock_file)
        mock_file.__exit__ = MagicMock(return_value=False)
        mock_h5py.File.return_value = mock_file
        mock_file.__getitem__ = MagicMock(return_value=MagicMock())

        result = safe_nir_read("/some/file.nir")

    mock_dict2nir.assert_called_once_with(fake_data)
    assert result is fake_graph


# ---------------------------------------------------------------------------
# safe_nir_read: unrelated TypeError — must re-raise
# ---------------------------------------------------------------------------


def test_safe_nir_read_reraises_unrelated_type_error():
    """When nir.read() raises TypeError NOT about 'type_check', it is re-raised as-is."""
    unrelated_error = TypeError("something completely different")
    with (
        patch("neurocnl._nir_compat.nir.read", side_effect=unrelated_error),
        pytest.raises(TypeError, match="something completely different"),
    ):
        safe_nir_read("/some/file.nir")


# ---------------------------------------------------------------------------
# safe_nir_read: fallback internals unavailable — RuntimeError
# ---------------------------------------------------------------------------


def test_safe_nir_read_raises_runtime_error_when_fallback_fails():
    """When fallback HDF5 path also fails (missing h5py/nir internals), a clear RuntimeError is raised."""
    type_check_error = TypeError("got an unexpected keyword argument 'type_check'")
    with (
        patch("neurocnl._nir_compat.nir.read", side_effect=type_check_error),
        patch("neurocnl._nir_compat.h5py", None),
        pytest.raises(RuntimeError, match="nir version incompatibility"),
    ):
        safe_nir_read("/some/file.nir")


# ---------------------------------------------------------------------------
# make_nir_graph: defensive retry on type_check rejection
# ---------------------------------------------------------------------------


def _minimal_graph_args() -> tuple[dict, list]:
    """Return minimal valid nodes/edges for make_nir_graph."""
    inp = nir.Input(input_type={"input": np.array([1])})
    out = nir.Output(output_type={"output": np.array([1])})
    return {"input": inp, "output": out}, [("input", "output")]


def test_make_nir_graph_retries_without_type_check_when_detection_wrong():
    """When NIR_HAS_TYPE_CHECK=True but NIRGraph still rejects type_check, make_nir_graph retries."""
    nodes, edges = _minimal_graph_args()
    fake_graph = MagicMock(spec=nir.NIRGraph)

    type_check_error = TypeError(
        "NIRGraph.__init__() got an unexpected keyword argument 'type_check'"
    )

    call_count = 0

    def fake_nir_graph(nodes, edges, **kwargs):
        nonlocal call_count
        call_count += 1
        if "type_check" in kwargs:
            raise type_check_error
        return fake_graph

    with (
        patch("neurocnl._nir_compat.NIR_HAS_TYPE_CHECK", True),
        patch("neurocnl._nir_compat.nir.NIRGraph", side_effect=fake_nir_graph),
    ):
        result = make_nir_graph(nodes=nodes, edges=edges, skip_type_check=True)

    assert call_count == 2  # first call raised, second call succeeded
    assert result is fake_graph
