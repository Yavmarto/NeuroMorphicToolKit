import textwrap
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import pytest

from neurosim.app.services.components import _invalidate_cache, load_components

VALID_CUSTOM_NODE = textwrap.dedent(
    """
    from nmtk_sdk import CustomNode, param, port

    class TestNeuron(CustomNode):
        name = "Test Neuron"
        category = "neurons"
        canvases = ["model"]
        frameworks = ["nengo"]
        author = "tester"

        @param(type="float", default=0.02, label="Tau")
        def tau_m(self): ...

        @port(direction="input", label="In")
        def spikes_in(self): ...

        def to_nengo(self, params):
            return object()
"""
)


@pytest.fixture(autouse=True)
def _reset_cache() -> Iterator[None]:  # noqa: ANN202
    _invalidate_cache()
    yield
    _invalidate_cache()


def test_custom_node_appears_in_registry(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    custom_dir = tmp_path / "custom_nodes"
    custom_dir.mkdir()
    (custom_dir / "test_neuron.py").write_text(VALID_CUSTOM_NODE)

    import neurosim.app.services.components as svc

    monkeypatch.setattr(svc, "CUSTOM_NODES_DIR", custom_dir)
    _invalidate_cache()

    components = load_components()
    custom = [c for c in components.values() if c.is_custom]
    assert len(custom) == 1
    assert custom[0].name == "Test Neuron"
    assert custom[0].is_custom is True
    assert custom[0].source_path is not None


def test_invalid_custom_node_is_skipped(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    custom_dir = tmp_path / "custom_nodes"
    custom_dir.mkdir()
    (custom_dir / "broken.py").write_text("def (((broken")

    import neurosim.app.services.components as svc

    monkeypatch.setattr(svc, "CUSTOM_NODES_DIR", custom_dir)
    _invalidate_cache()

    # Should not raise — broken file is skipped with a warning
    components = load_components()
    assert all(not c.is_custom for c in components.values())


def test_dangerous_import_node_still_loads_with_warning(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, caplog: Any
) -> None:
    dangerous = textwrap.dedent(
        """
        import os
        from nmtk_sdk import CustomNode

        class DangerNode(CustomNode):
            name = "Danger"
            category = "neurons"
            canvases = ["model"]
            frameworks = ["nengo"]

            def to_nengo(self, params):
                return object()
    """
    )
    custom_dir = tmp_path / "custom_nodes"
    custom_dir.mkdir()
    (custom_dir / "danger.py").write_text(dangerous)

    import neurosim.app.services.components as svc

    monkeypatch.setattr(svc, "CUSTOM_NODES_DIR", custom_dir)
    _invalidate_cache()

    import logging

    with caplog.at_level(logging.WARNING):
        components = load_components()

    custom = [c for c in components.values() if c.is_custom]
    assert len(custom) == 1  # loaded despite warning
    assert any(
        "dangerous" in r.message.lower() or "os" in r.message for r in caplog.records
    )
