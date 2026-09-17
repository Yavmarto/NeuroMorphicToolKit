"""neurocnl — Controlled Natural Language for neuromorphic computing.

Parse plain-English specifications, validate against physical invariants,
and compile to NIR graphs.

Quick start::

    from neurocnl import parse, validate, compile_to_nir

    spec = "The network MUST contain an excitatory input population of 4 neurons\\n..."
    graph = compile_to_nir(spec)
"""

from importlib import import_module
from typing import Any

__version__ = "0.6.0"

from neurocnl.cnl.types import ParsedSentence
from neurocnl.compile import (
    CompileError,
    Diagnostic,
    compile_pipeline_config,
    compile_to_nir,
)
from neurocnl.generation.assertion_generator import generate_assertions
from neurocnl.layers.layer1_validator import validate
from neurocnl.nir_cnl.pipeline_config import PipelineConfig
from neurocnl.pipeline import (
    NirImportDiagnostic,
    NirImportError,
    PipelineResult,
    generate_cnl_from_nir,
    run_pipeline,
)
from neurocnl.spike_encoding import delta_encode, rate_encode, temporal_encode
from neurocnl.training_api import fit

__all__ = [
    "__version__",
    "ParsedSentence",
    "validate",
    "generate_assertions",
    "run_pipeline",
    "PipelineResult",
    "fit",
    "rate_encode",
    "temporal_encode",
    "delta_encode",
    "compile_to_nir",
    "compile_pipeline_config",
    "PipelineConfig",
    "CompileError",
    "Diagnostic",
    "generate_cnl_from_nir",
    "NirImportDiagnostic",
    "NirImportError",
]

_OPTIONAL_VIZ_EXPORTS = {
    "spike_raster",
    "membrane_traces",
    "network_topology",
    "weight_evolution",
    "to_html",
}


def __getattr__(name: str) -> Any:
    """Lazily expose optional visualization helpers.

    Importing :mod:`neurocnl` should stay lightweight for server startup.
    The Matplotlib-backed visualization module is therefore imported only
    when one of its public helpers is actually accessed.
    """
    if name not in _OPTIONAL_VIZ_EXPORTS:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")

    try:
        visualization = import_module("neurocnl.visualization")
        value = getattr(visualization, name)
    except ImportError as exc:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}") from exc

    globals()[name] = value
    return value


def __dir__() -> list[str]:
    return sorted(set(globals()) | _OPTIONAL_VIZ_EXPORTS)
