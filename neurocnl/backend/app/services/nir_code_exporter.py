"""Build a readable textual NIR representation for Studio previews."""

from __future__ import annotations

import json
from typing import Any

import nir
import numpy as np


def export_nir_code(graph: nir.NIRGraph) -> str:
    """Render a deterministic JSON view of a NIR graph."""
    return json.dumps(_normalize(graph.to_dict()), indent=2, sort_keys=False)


def _normalize(value: Any) -> Any:
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, dict):
        return {key: _normalize(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_normalize(item) for item in value]
    if isinstance(value, tuple):
        return [_normalize(item) for item in value]
    return value
