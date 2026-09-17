"""Tests for optional ``metadata`` kwargs across nir node constructors."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import numpy as np
import pytest

from neurocnl._nir_compat import (
    NIR_HAS_LINEAR_METADATA,
    make_nir_linear,
    make_nir_node,
    nir_node_accepts_metadata,
)

nir = pytest.importorskip("nir")


def test_nir_linear_metadata_flag_matches_signature() -> None:
    assert nir_node_accepts_metadata(nir.Linear) is NIR_HAS_LINEAR_METADATA


def test_make_nir_linear_omits_metadata_when_unsupported() -> None:
    weight = np.ones((1, 1), dtype=float)
    metadata = {"weight_init": "xavier", "seed": 42}

    with patch(
        "neurocnl._nir_compat.nir_node_accepts_metadata",
        return_value=False,
    ):
        node = make_nir_linear(weight=weight, metadata=metadata)

    assert np.array_equal(node.weight, weight)


def test_make_nir_linear_forwards_metadata_when_supported() -> None:
    if not NIR_HAS_LINEAR_METADATA:
        pytest.skip("installed nir.Linear does not accept metadata")

    weight = np.ones((1, 1), dtype=float)
    metadata = {"weight_init": "xavier", "seed": 42}
    node = make_nir_linear(weight=weight, metadata=metadata)

    assert node.metadata == metadata


def test_make_nir_node_delegates_to_constructor_without_metadata() -> None:
    sentinel = MagicMock()
    weight = np.eye(2)

    with (
        patch(
            "neurocnl._nir_compat.nir_node_accepts_metadata",
            return_value=False,
        ),
        patch("neurocnl._nir_compat.nir.Linear", sentinel),
    ):
        make_nir_node(nir.Linear, weight=weight, metadata={"label": "w_sensor_actuator"})

    sentinel.assert_called_once_with(weight=weight)
