"""NIR-native CNL package.

Public surface for the NIR-native Controlled Natural Language pipeline.
The three executable components — :class:`NIR_Renderer`,
:class:`NIR_CNL_Parser`, and :class:`NIR_Compiler` — together with their
shared error and record types are re-exported here so callers can write
either of the canonical import forms::

    from neurocnl.nir_cnl import NIR_Renderer, NIR_CNL_Parser, NIR_Compiler
    from neurocnl.nir_cnl import ParseError, RenderError, CompileError, Diagnostic

The data-only intermediate-record types (:class:`NIRNodeRecord`,
:class:`NIREdgeRecord`, :class:`NetworkContainer`, :class:`ArraySpec`,
and :class:`ArrayValues`) are also re-exported because they are part of
the parser/compiler contract surface and downstream code occasionally
needs to inspect them directly.
"""

from __future__ import annotations

from neurocnl.nir_cnl.compiler import NIR_Compiler
from neurocnl.nir_cnl.errors import CompileError, Diagnostic, ParseError, RenderError
from neurocnl.nir_cnl.ir_types import (
    ArraySpec,
    ArrayValues,
    EvaluationConfigRecord,
    ExportConfigRecord,
    NetworkContainer,
    NIREdgeRecord,
    NIRNodeRecord,
    TrainingConfigRecord,
)
from neurocnl.nir_cnl.parser import NIR_CNL_Parser
from neurocnl.nir_cnl.pipeline_config import PipelineConfig, extract_pipeline_config
from neurocnl.nir_cnl.renderer import NIR_Renderer

__all__ = [
    # Executable components
    "NIR_Renderer",
    "NIR_CNL_Parser",
    "NIR_Compiler",
    # Error types
    "ParseError",
    "RenderError",
    "CompileError",
    "Diagnostic",
    # Intermediate record types
    "NIRNodeRecord",
    "NIREdgeRecord",
    "NetworkContainer",
    "ArraySpec",
    "ArrayValues",
    "TrainingConfigRecord",
    "EvaluationConfigRecord",
    "ExportConfigRecord",
    # Pipeline config extraction
    "PipelineConfig",
    "extract_pipeline_config",
]
