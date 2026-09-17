"""Regression tests for lazy optional visualization imports."""

import importlib
import sys


def test_import_neurocnl_does_not_eagerly_import_visualization() -> None:
    # Remove only the visualization sub-module, not the top-level package,
    # to avoid polluting other tests that rely on `neurocnl` being importable.
    sys.modules.pop("neurocnl.visualization", None)

    import neurocnl  # noqa: F401

    assert "neurocnl.visualization" not in sys.modules


def test_accessing_visualization_symbol_imports_module_on_demand() -> None:
    sys.modules.pop("neurocnl.visualization", None)

    neurocnl = importlib.import_module("neurocnl")

    try:
        _ = neurocnl.spike_raster
    except AttributeError:
        # Core install: optional viz helpers stay absent if matplotlib is unavailable.
        assert "neurocnl.visualization" not in sys.modules
    else:
        assert "neurocnl.visualization" in sys.modules
