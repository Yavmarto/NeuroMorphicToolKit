"""Shared diagnostics for NIR->framework converters.

One canonical place to fail loudly when a converter's per-node dispatch loop
encounters a node type it does not recognize, instead of silently skipping
it. Message shape mirrors sinabs_io.py's existing raise (the one converter
that already reports a `supported_types` list alongside the unsupported type).
"""

from __future__ import annotations

from typing import NoReturn

import nir


def raise_unsupported_node(
    node: nir.NIRNode,
    converter_name: str,
    supported_types: tuple[type, ...],
    *,
    node_name: str,
) -> NoReturn:
    """Raise NotImplementedError for a NIR node type a converter cannot handle."""
    supported_names = ", ".join(t.__name__ for t in supported_types)
    raise NotImplementedError(
        f"NIR node type '{type(node).__name__}' (node '{node_name}') is not "
        f"supported in {converter_name} conversion. Supported types: "
        f"{supported_names}."
    )
